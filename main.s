;
;
;
;
;
;
;
;
;

; ports of the 65C22 versatile interface adapter.
PORTB = $6000    ; port B of the versatile interface.
PORTA = $6001    ; port A of the versatile interface.
DDRB  = $6002    ; port B is controlled by DDRB at 6002.
DDRA  = $6003    ; port A is controlled by DDRA at 6003.
SR    = $600a    ; shift register.
ACR   = $600b    ; auxiliary control register.
PCR   = $600c    ; preipheral control register.
IFR   = $600d    ; interrupt flag register.
IER   = $600e    ; interrupt enable register.

; hardware uses 3 top bits of PORTA to control the LDC display. PORTA ~ EWS*****.
E  = %10000000   ; enables the LCD display for control.
RW = %01000000   ; 0 to write, 1 to read.
RS = %00100000   ; 0 to access Instruction Register (IR), 1 for Data Register (DR).

; constants.
gotoline1 = %10000000
gotoline2 = %11000000

button_left   = %00000001 ; buttons indices.
button_up     = %00000010
button_right  = %00000100
button_down   = %00001000
button_select = %00010000

; video.
vram_size           = 56  ; the size of the vRAM, 0-indexed.
; positions.
up_pos              = 0   ; possible positions.
down_pos            = 40
obst_init_pos       = $0f ; change 4 LSB, from 0 to f.
; sprites.
player_sprite       = "0" ; sprite for the player.
missile_sprite      = "-" ; sprite for the missile.
obstacle_sprite     = "0" ; sprite for the obstacles.
can_shoot_sprite    = $a5 ; the sprite indicating that the player can shoot.
charged_shot_sprite = "*" ; the sprite indicating a shot is charged.
; misc.
missile_speed       = 2   ; the speed of the missile.
obst_active         = $80
; game menu management.
INITIALIZE_GAME     = %00000001
GAMEPLAY            = %00000010
GAME_OVER           = %00000011
MENU                = %00000100
OPTIONS             = %00000101
DEFAULT_SELECTION   = %00010000
GAMEMODE_EASY       = %01000000
GAMEMODE_NORMAL     = %10000000
GAMEMODE_HARD       = %11000000


; program variables addresses.
; zero page.
ptr16     = $0000 ; 1 word, 16-bit pointer.
obstacles = $0002 ; pointer to a *-byte array of obstacles, i.e. bytes.

; functions.
buffer8            = $0200 ; 1 byte, 8-bit buffer.
buffer16           = $0201 ; 1 word, 16-bit buffer.
div10              = $0203 ; 1 word, used as dividend in print16.
mod10              = $0205 ; 1 word, used as remainder in print16.
counter            = $0207 ; 1 word.
message            = $0209 ; 6 bytes (including the null-terminating character).
; I/O.
buttons            = $020f ; 1 byte, states of all buttons.
changes            = $0210 ; 1 byte, indicate changes of button presses.
; game variables.
player_charge      = $0211 ; 1 byte, the player's charge.
player_status      = $0212 ; 1 byte ~ *,pos,rdy,can,health*4
player_score       = $0213 ; 1 word
missile_status     = $0215 ; 1 byte ~ y,off,p3,p2,p1,p0,b1,b0
game_state         = $0216 ; 1 byte current state of the game.
; gamemode variables.
charged_shot       = $0217 ; 1 byte, the value to charge.
player_health      = $0218 ; 1 byte, change 4 LSB, from 0 to f.
new_obst_threshold = $0219 ; 1 byte, the threshold to spawn a new obstacle.
obstacle_speed     = $021a ; 1 byte, the speed of the obstacles.
obst_full_health   = $021b ; 1 byte, change 4 MSB, from 0 to 3.
nb_obstacles       = $021c ; 1 byte, there is a maximum of * obstacles.


vram          = $0500 ; 56 bytes of vRAM for the LCD.

; pseudo-random number generator variables.
; put at the far end of RAM.
prng_seed = $3ffb
prng_mod  = $3ffc
prng_mult = $3ffd
prng_inc  = $3ffe
prng_num  = $3fff

  .org $8000

;; resets the internals of the CPU and interface for proper use.
reset:
  ; initialize the processor.
  ldx #$ff
  txs                     ; set the stack pointer to being #ff.

  ; initialize the pRNG.
  jsr irand
  lda $0100 ; arbitrary seed.
  jsr srand

  ; initialize the LCD.
  lda #%11111111          ; set all pins on port B to output.
  sta DDRB
  lda #%11100000          ; set top 3 pins on port A to output.
  sta DDRA

  lda #%00111000          ; set 8-bit mode; 2-line display; 5x8 font.
  jsr lcd_instruction
  lda #%00001100          ; display on; cursor off; blink off.
  jsr lcd_instruction
  lda #%00000110          ; increment and shift cursor; don't shift display.
  jsr lcd_instruction
  lda #%00000001          ; clear display.
  jsr lcd_instruction

  ; initialize the W65C22 interface.
  lda #$82  ; activate CA1.
  sta IER
  lda #$02  ; CA1 ~ positive active edge.
  sta PCR

  ; initialize button status.
  lda #$00    ; buttons released.
  sta buttons
  lda #0      ; buttons still.
  sta changes

  ; initialize the game internal state.
  lda #MENU
  ora #DEFAULT_SELECTION
  ora #GAMEMODE_NORMAL
  sta game_state





game_loop:
  ;; read the buttons.
read_buttons:
  lda PORTA
  eor #$ff     ; buttons are negative active.
  tay
  eor buttons  ; look at changes.
  sty buttons  ; save new buttons and changes.
  sta changes





  ;; determine the game state and jump to code.
game_state_treatment:
  lda game_state
  and #%00001111
is_menu_open:
  cmp #MENU
  beq menu
is_in_options:
  cmp #OPTIONS
  bne is_initialization_needed
  jmp options
is_initialization_needed:
  cmp #INITIALIZE_GAME
  bne is_game_playing
  jmp initialize_game
is_game_playing:
  cmp #GAMEPLAY
  bne is_game_over
  jmp gameplay
is_game_over:
  cmp #GAME_OVER
  bne goto_unknown_error
  jmp game_over
goto_unknown_error:
  jmp unknown_error





menu:
  jsr empty_vram

  lda #<menu_bg  ; copy the message to the vram.
  sta ptr16
  lda #>menu_bg
  sta ptr16 + 1
  jsr fill_bg_vram

  lda game_state  ; look at what button is selected.
  and #%00010000
  bne menu_to_options  ; selection on "options".
  lda game_state
  and #%00100000
  bne menu_to_play  ; selection on "play".
  jmp unknown_error
menu_to_options:
  lda #">" ; mark the selection.
  sta vram + 40
  lda #"<"
  sta vram + 48
  lda buttons  ; if right, go to other button.
  and changes
  and #button_right
  bne menu_from_options_to_play
  lda buttons  ; if select, go in "options".
  and changes
  and #button_select
  bne menu_goto_options
  jmp menu_checked
menu_from_options_to_play:
  lda game_state  ; change button selection.
  and #%11001111
  ora #%00100000
  sta game_state
  jmp menu_checked
menu_goto_options:
  lda game_state  ; change game_state.
  and #%11110000
  ora #(OPTIONS | DEFAULT_SELECTION)
  sta game_state
  jmp menu_checked
menu_to_play:
  lda #">"  ; mark the selection.
  sta vram + 50
  lda #"<"
  sta vram + 55
  lda buttons  ; if left, go to other button.
  and changes
  and #button_left
  bne menu_from_play_to_options
  lda buttons  ; if select, go to "play".
  and changes
  and #button_select
  bne menu_goto_play
  jmp menu_checked
menu_from_play_to_options:
  lda game_state  ; change button selection.
  and #%11001111
  ora #%00010000
  sta game_state
  jmp menu_checked
menu_goto_play:  ; change game_state.
  lda game_state
  and #%11110000
  ora #INITIALIZE_GAME
  sta game_state
menu_checked:

  jsr flip_vram

  jmp game_loop





options:
  jsr empty_vram

  lda #<options_bg ; copy the message to the vram.
  sta ptr16
  lda #>options_bg
  sta ptr16 + 1
  jsr fill_bg_vram

  lda game_state
  and #%11000000
  cmp #GAMEMODE_EASY
  beq options_print_easy_mode
  cmp #GAMEMODE_NORMAL
  beq options_print_normal_mode
  cmp #GAMEMODE_HARD
  beq options_print_hard_mode
  jmp unknown_error
options_print_easy_mode:
  lda #<easy_mode_msg
  sta ptr16
  lda #>easy_mode_msg
  sta ptr16 + 1
  jmp options_print_mode
options_print_normal_mode:
  lda #<normal_mode_msg
  sta ptr16
  lda #>normal_mode_msg
  sta ptr16 + 1
  jmp options_print_mode
options_print_hard_mode:
  lda #<hard_mode_msg
  sta ptr16
  lda #>hard_mode_msg
  sta ptr16 + 1

options_print_mode:
  ldy #0
  ldx #9
options_print_mode_loop:
  lda (ptr16),y
  beq options_print_mode_end
  sta vram,x
  inx
  iny
  jmp options_print_mode_loop
options_print_mode_end:

  lda game_state  ; look at what button is selected.
  and #%00010000
  bne options_to_menu  ; selection on "back".
  lda game_state
  and #%00100000
  bne options_to_mode  ; selection on "mode".
  jmp unknown_error
options_to_menu:
  lda #">" ; mark the selection.
  sta vram + 50
  lda #"<"
  sta vram + 55
  lda buttons  ; if up, go to other button.
  and changes
  and #button_up
  bne options_from_back_to_mode
  lda buttons  ; if select, go in "menu".
  and changes
  and #button_select
  bne options_goto_menu
  jmp options_checked
options_from_back_to_mode:
  lda game_state  ; change button selection.
  and #%11001111
  ora #%00100000
  sta game_state
  jmp options_checked
options_goto_menu:
  lda game_state  ; change game_state.
  and #%11110000
  ora #(MENU | DEFAULT_SELECTION)
  sta game_state
  jmp options_checked
options_to_mode:
  lda #">"  ; mark the selection.
  sta vram + 0
  lda #"<"
  sta vram + 5
  lda buttons  ; if down, go to other button.
  and changes
  and #button_down
  bne options_from_mode_to_back
  lda buttons  ; if select, go to "mode".
  and changes
  and #button_select
  bne options_change_mode
  jmp options_checked
options_from_mode_to_back:
  lda game_state  ; change button selection.
  and #%11001111
  ora #%00010000
  sta game_state
  jmp options_checked
options_change_mode:  ; change game_state.
  lda game_state
  clc
  adc #%01000000
  bcc options_mode_no_wrap
options_mode_wrap:
  ora #%01000000
options_mode_no_wrap:
  sta game_state
options_checked:

  jsr flip_vram

  jmp game_loop





  ;; if player is dead, print GAME OVER.
game_over:
  jsr empty_vram

  lda #<game_over_bg ; copy the message to the vram.
  sta ptr16
  lda #>game_over_bg
  sta ptr16 + 1
  jsr fill_bg_vram

  lda player_score ; compute score in message.
  sta div10
  lda player_score + 1
  sta div10 + 1
  jsr print16_decimal

  ldx #45 ; blit the computed score to vram.
  ldy #0
game_over_screen_blit_scrore:
  lda message,y
  beq game_over_screen_score_blit
  sta vram,x
  inx
  iny
  jmp game_over_screen_blit_scrore
game_over_screen_score_blit

  lda game_state  ; look at what button is selected.
  and #%00010000
  bne game_over_to_menu  ; selection on "menu".
  lda game_state
  and #%00100000
  bne game_over_to_new  ; selection on "new".
  jmp unknown_error
game_over_to_menu:
  lda #">" ; mark the selection.
  sta vram + 10
  lda #"<"
  sta vram + 15
  lda buttons  ; if down, go to other button.
  and changes
  and #button_down
  bne game_over_from_menu_to_new
  lda buttons  ; if select, go in "new".
  and changes
  and #button_select
  bne game_over_goto_menu
  jmp game_over_checked
game_over_from_menu_to_new:
  lda game_state  ; change button selection.
  and #%11001111
  ora #%00100000
  sta game_state
  jmp game_over_checked
game_over_goto_menu:
  lda game_state
  and #%11110000
  ora #(MENU | DEFAULT_SELECTION)  ; change game_state.
  sta game_state
  jmp game_over_checked
game_over_to_new:
  lda #">"  ; mark the selection.
  sta vram + 51
  lda #"<"
  sta vram + 55
  lda buttons  ; if up, go to other button.
  and changes
  and #button_up
  bne game_over_from_new_to_menu
  lda buttons  ; if select, go to "play".
  and changes
  and #button_select
  bne game_over_goto_new
  jmp game_over_checked
game_over_from_new_to_menu:
  lda game_state  ; change button selection.
  and #%11001111
  ora #%00010000
  sta game_state
  jmp game_over_checked
game_over_goto_new:  ; change game_state.
  lda game_state
  and #%11110000
  ora #INITIALIZE_GAME
  sta game_state
game_over_checked:

  jsr flip_vram

bottom_of_game_over:
  jmp game_loop





  ; initialize game variables with gamemode.
initialize_game:
  lda game_state
  and #%11000000
  tax
  cmp #GAMEMODE_EASY
  beq initialize_easy_gamemode
  txa
  cmp #GAMEMODE_NORMAL
  beq initialize_normal_gamemode
  txa
  cmp #GAMEMODE_HARD
  beq initialize_hard_gamemode
  jmp unknown_error
initialize_easy_gamemode:
  lda #2     ; charged_shot
  sta charged_shot
  lda #$0f   ; player_health
  sta player_health
  lda #$10   ; new_obst_threshold
  sta new_obst_threshold
  lda #$02   ; obstacle_speed
  sta obstacle_speed
  lda #$10   ; obst_full_health
  sta obst_full_health
  lda #3     ; nb_obstacles
  sta nb_obstacles
  jmp gamemode_initialization_done
initialize_normal_gamemode:
  lda #8     ; charged_shot
  sta charged_shot
  lda #$08   ; player_health
  sta player_health
  lda #$04   ; new_obst_threshold
  sta new_obst_threshold
  lda #$08   ; obstacle_speed
  sta obstacle_speed
  lda #$30   ; obst_full_health
  sta obst_full_health
  lda #5     ; nb_obstacles
  sta nb_obstacles
  jmp gamemode_initialization_done
initialize_hard_gamemode:
  lda #32    ; charged_shot
  sta charged_shot
  lda #$04   ; player_health
  sta player_health
  lda #$02   ; new_obst_threshold
  sta new_obst_threshold
  lda #$10   ; obstacle_speed
  sta obstacle_speed
  lda #$30   ; obst_full_health
  sta obst_full_health
  lda #7     ; nb_obstacles
  sta nb_obstacles

gamemode_initialization_done
  ; initialize game_state.
  lda game_state
  and #%11110000
  ora #GAMEPLAY
  sta game_state
  ; initialize player.
  lda charged_shot  ; up + no charge.
  sta player_charge
  jsr rand  ; pick random line.
  lda prng_num
  and #%01000000
  ora #%00010000  ; able to charge.
  ora player_health
  sta player_status
  lda #0
  sta player_score
  sta player_score + 1
  lda #%01000000     ; missile disabled.
  sta missile_status
  ; initialize obstacles.
  lda #$00           ; array of obstacles starts at $0300.
  sta obstacles
  lda #$03
  sta obstacles + 1
  lda nb_obstacles  ; there are twice as many bytes.
  clc               ; as there are obstacles.
  adc nb_obstacles
  tay
  dey    ; y <- 2 * nb_obstacles - 1
  lda #0 ; empty obstacles at the beginning.
init_obstacles_loop:
  sta (obstacles),y
  dey
  bpl init_obstacles_loop

game_initialization_done
  jmp game_loop





gameplay:
; detect if the "up" button is down.
is_button_up_pressed:
  lda buttons
  and #button_up
  beq button_up_not_pressed
button_up_pressed:
  lda changes             ; check if button was pressed.
  and #button_up
  beq button_up_not_pressed
  lda player_status       ; check if player was down (=1).
  pha
  and #%01000000
  beq is_button_left_pressed
  pla
  and #%10111111          ; move the player up.
  sta player_status
  jmp is_button_left_pressed
button_up_not_pressed:

; detect if the "down" button is down.
is_button_down_pressed:
  lda buttons
  and #button_down
  beq button_down_not_pressed
button_down_pressed:
  lda changes             ; check if button was pressed.
  and #button_down
  beq button_down_not_pressed
  lda player_status       ; check if player was up (=0).
  tax
  and #%01000000
  bne is_button_left_pressed
  txa
  ora #%01000000          ; move the player down.
  sta player_status
  jmp is_button_left_pressed
button_down_not_pressed:

is_button_left_pressed:
  lda buttons
  and #button_left
  beq button_left_not_pressed
button_left_pressed:
  lda changes             ; check if button was pressed.
  and #button_left
  beq button_left_not_pressed
  lda game_state
  and #%11000000
  ora #(MENU | DEFAULT_SELECTION)
  sta game_state
  jmp game_loop
button_left_not_pressed:

; detect if the "select" button is down.
is_button_select_pressed:
  lda buttons             ; check if button enter was pressed.
  and #button_select
  beq button_select_not_pressed
button_select_pressed:
  lda player_status       ; check if player can shoot.
  and #%00010000
  beq no_charging
charging:
  dec player_charge       ; decrement the player charge.
  jmp buttons_read_done
button_select_not_pressed:
no_charging:              ; if button released, reset the charge.
  lda changes
  and #button_select
  beq buttons_read_done

is_missile_launchable:
  lda player_status       ; no if not ready.
  and #%00100000
  beq missile_not_launchable
  lda player_status       ; no if player can shoot.
  and #%00010000
  bne missile_not_launchable
  lda missile_status      ; cannot shoot when already shooting.
  and #%01000000
  beq missile_not_launchable
missile_launch:           ; launch missile...
  lda player_status
  and #%01000000
  bne launch_missile_down ; (where is missile launched from?)
launch_missile_up:        ; ... up...
  lda #%00000000
  sta missile_status
  jmp missile_launch_done
launch_missile_down:      ; ... or down.
  lda #%10000000
  sta missile_status
  jmp missile_launch_done
missile_not_launchable:
  lda player_status       ; reset player's charge only
  and #%00010000          ; when it can shoot.
  beq missile_launch_done
  lda charged_shot
  sta player_charge
missile_launch_done:
  lda player_status
  and #%11011111
  sta player_status

buttons_read_done:





  ;; update the player internal status.
update_player:
can_player_shoot:
  lda player_status
  and #%00010000
  bne player_can_shoot
player_cannot_shoot: ; increment back player's charge
  lda player_charge  ; until it is full -> can shoot again.
  cmp charged_shot
  bne player_overload
player_can_shoot_again:
  lda player_status
  ora #%00010000     ; set the "can shoot" bit.
  and #%11011111     ; and reset the "ready" bit.
  sta player_status
  jmp player_update_done
player_overload:
  lda player_status
  and #%00110000
  bne is_charge_done
  inc player_charge
player_can_shoot:
is_charge_done:
  lda player_charge  ; is charge done, i.e. =0?
  bne player_needs_charge
player_charge_done:  ; yes, update.
  lda player_status
  ora #%00100000     ; set the "ready" bit.
  and #%11101111     ; and reset the "can shoot" bit.
  sta player_status
player_needs_charge: ; no, continue charging.
player_update_done:





  ;; update the missile if needed.
update_missile:
is_missile_launched:
  lda missile_status      ; is missile one the way?
  and #%01000000
  bne missile_not_launched
missile_launched:         ; yes, update it.
  lda missile_status
  clc
  adc #missile_speed      ; add speed to move right.
  and #%10111111          ; remove the possible carry.
  sta missile_status
is_missile_outside:
  and #%00111111          ; is missile outside the LCD?
  bne missile_inside
missile_outside:          ; yes, kill it.
  lda #%01000000          ; set missile enable bit.
  sta missile_status
missile_inside:           ; no killing.
missile_not_launched:     ; no update.
missile_update_done:





  ;; spawn new obstacles.
obstacles_spawn:
  jsr rand              ; generate random number
  lda prng_num          ; and compare it.
  cmp new_obst_threshold
  bcs no_obstacle_spawn
; run through the obstacle array, looking for empty one.
spawn_an_obstacle:
  lda nb_obstacles  ; there are twice as many bytes.
  clc               ; as there are obstacles.
  adc nb_obstacles
  tay
  dey ; Y <- 2 * nb_obstacles - 1
obstacles_spawn_loop:
is_obstacle_active:
  lda (obstacles),y  ; the status of the obstacle.
  and #%10000000
  bne active_obstacle_found
inactive_obstacle_found:
  phy      ; generate obstacle properties.
  jsr rand
  ply
where_obstacle_spawn:
  lda prng_num
  and #%01000000 ; random line.
  ora #obst_active
  ora obst_full_health
  ora #obst_init_pos
spawn_obstacle: ; spawn the obstacle.
  sta (obstacles),y
  dey ; put 256 in obstacle's position buffer.
  lda #$ff
  sta (obstacles),y
  jmp obstacles_spawned
active_obstacle_found:
  dey
obstacle_spawn_done:
  dey
  bpl obstacles_spawn_loop
no_obstacle_spawn:
obstacles_spawned:





  ;; update the obstacles.
update_obstacles:
  lda nb_obstacles  ; there are twice as many bytes.
  clc               ; as there are obstacles.
  adc nb_obstacles
  tay
  dey ; Y <- 2 * nb_obstacles - 1
update_obstacles_loop:
is_obstacle_on:
  lda (obstacles),y  ; obstacle's status.
  and #%10000000
  beq off_obstacle_found
on_obstacle_found:
  dey
  lda (obstacles),y  ; obstacle's position buffer.
  sec
  sbc obstacle_speed
  sta (obstacles),y  ; if buffer wraps around.
  bcc move_obstacle  ; move the obstacle.
do_not_move_obstacle:
  jmp obstacle_updated
move_obstacle:
  iny
  lda (obstacles),y  ; obstacle's status.
  pha
  and #%00001111     ; kill if position is 0.
  beq kill_obstacle
do_not_kill_obstacle:
  pla
  dec a              ; otherwise, move left.
  sta (obstacles),y
  dey
  jmp obstacle_updated
kill_obstacle:
  pla
  lda #0  ; zero out the status.
  sta (obstacles),y
  dey
  jmp obstacle_updated
off_obstacle_found: ; decrement y in any case
  dey               ; to inspect next obstacle.
obstacle_updated:
  dey
  bpl update_obstacles_loop
obstacles_updated:





  ;; handle all the collisions between objects.
  ;; namely between all obstacles and the player and missile.
collisions_handling:
  lda nb_obstacles  ; there are twice as many bytes.
  clc               ; as there are obstacles.
  adc nb_obstacles
  tay
  dey ; Y <- 2 * nb_obstacles - 1
collisions_handling_loop:
can_obstacle_collide:
  lda (obstacles),y  ; obstacle's status.
  and #%10000000
  bne obstacle_can_collide ; trick to jump to bottom.
  jmp obstacle_cannot_collide
obstacle_can_collide:
is_there_obstacle_missile_collision:
  lda (obstacles),y
  and #%01000000         ; check the line.
  clc                    ; against the missile.
  rol
  sta buffer8
  lda missile_status     ; make sure missile is active.
  and #%01000000
  bne no_obstacle_missile_collision
  lda missile_status     ; missile's line.
  and #%10000000
  eor buffer8            ; xor to check equality.
  bne no_obstacle_missile_collision
obstacle_missile_on_same_line:
  lda (obstacles),y
  and #%00001111         ; check the column.
  sta buffer8
  lda missile_status     ; missile's column.
  and #%00111100
  clc
  ror
  ror
  cmp buffer8
  bne no_obstacle_missile_collision
obstacle_missile_collision:
  inc player_score       ; increment player scrore.
  bne no_player_score_carry
player_score_carry:
  inc player_score + 1
no_player_score_carry:
  lda #%01000000         ; set missile enable bit.
  sta missile_status
  lda (obstacles),y      ; remove 1 HP to the obstacle.
  sec
  sbc #%00010000
  pha
  and #%00110000         ; kill it if no HP left.
  bne obstacle_not_destroyed_by_missile
obstacle_destroyed_by_missile:
  pla
  lda #0
  sta (obstacles),y
  jmp collision_handled
obstacle_not_destroyed_by_missile:
  pla
  sta (obstacles),y      ; store the new status.
no_obstacle_missile_collision:
is_there_obstacle_player_collision:
  lda (obstacles),y
  eor player_status
  and #%01000000         ; check the line.
  bne no_obstacle_player_collision
obstacle_player_on_same_line:
  lda (obstacles),y
  and #%00001111         ; check the column.
  bne no_obstacle_player_collision
obstacle_player_collision:
  lda (obstacles),y
  and #%00110000
  clc
  ror
  ror
  ror
  ror
  sta buffer8
  lda player_status      ; remove the number of HP from the player.
  and #%00001111
  sec
  sbc buffer8
  pha  ; stash the new HPs.
  bcs player_is_alive
player_is_dead:
  lda game_state
  and #%11110000
  ora #(GAME_OVER | DEFAULT_SELECTION)
  sta game_state
player_is_alive:
in_both_cases:
  pla            ; store new HPs in player_status.
  and #%00001111
  sta buffer8
  lda player_status
  and #%11110000
  clc
  adc buffer8
  sta player_status
remove_obstacle:
  lda #0                 ; remove the obstacle.
  sta (obstacles),y
no_obstacle_player_collision:
obstacle_cannot_collide: ; decrement y in any case
collision_handled:       ; to inspect next obstacle.
  dey
  dey
  bmi collisions_handled ; trick to jump at the top.
  jmp collisions_handling_loop
collisions_handled:





  ;; show the scene.
show_scene:

  jsr empty_vram

blit_player:
where_is_player:
  lda player_status
  and #%01000000
  beq player_is_up   ; depends on player position.
player_is_down:
  ldx #down_pos
  jmp blit_player_sprite
player_is_up:
  ldx #up_pos
blit_player_sprite:  ; blit player sprite depending on health.
  lda player_status
  and #%00001111
  tay
  lda digits,y
  sta vram,x
blit_player_sprite_done:
blit_player_done:


blit_shot_preview:
blit_can_player_shoot
  lda player_status     ; visual indicator of ability to charge.
  and #%00010000
  beq blit_player_cannot_shoot
blit_player_can_shoot:
blit_shoot_step:
  lda player_charge     ; two cases depending on the value of charge.
  cmp charged_shot
  bne blit_charging
blit_not_charging:
  inx
  lda #can_shoot_sprite
  sta vram,x
  dex
  jmp blit_shot_preview_done
blit_charging:
  inx
  lda #charged_shot_sprite
  sta vram,x
  dex
blit_player_cannot_shoot:
blit_shot_preview_done:


missile_blit:
is_missile_raedy:
  lda player_status     ; is a missile ready?
  and #%00100000
  beq blit_missile_not_ready
  lda missile_status
  and #%01000000
  beq blit_is_missile_launched
blit_missile_preview:   ; yes, blit a preview.
  lda #missile_sprite
  inx
  sta vram,x
blit_missile_not_ready: ; no.
blit_is_missile_launched:
  lda missile_status    ; is missile launched?
  and #%01000000
  bne blit_missile_not_launched
blit_missile_launched:           ; yes, blit it.
  clc ; clear C for the ror.
where_is_missile:
  lda missile_status
  and #%10000000        ; where is missile launched from?
  pha
  lda missile_status
  and #%00111100        ; isolate B2-B5, roll twice and offset.
  ror
  ror
  tay ; store position in Y.
  pla
  bne missile_is_down
missile_is_up:          ; from 1st line.
  tya
  adc #up_pos
  jmp blit_missile
missile_is_down:        ; from second line.
  tya
  adc #down_pos
blit_missile:           ; blit the missile...
  tax
  lda #missile_sprite
  sta vram,x
  inx ; ...twice to make it more visible.
  sta vram,x
blit_missile_not_launched:
missile_blit_done:


obstacles_blit:
  lda nb_obstacles
  clc
  adc nb_obstacles
  tay
  dey ; Y <- 2 * nb_obstacles - 1
obstacles_blit_loop:
blit_is_obstacle_on
  lda (obstacles),y ; the obstacle's status.
  and #%10000000
  beq blit_obstacle_is_off
blit_obstacle_is_on:
  lda (obstacles),y
  and #%00001111    ; the obstacle's position in X.
  tax
blit_where_is_obstacle:
  lda (obstacles),y
  and #%01000000    ; the obstacle's line.
  clc
  beq blit_obstacle_is_up
blit_obstacle_is_down:
  txa  ; offset the position.
  adc #down_pos
  jmp blit_obstacle
blit_obstacle_is_up:
  txa  ; offset the position.
  adc #up_pos
blit_obstacle:
  pha               ; change sprite based on health.
  lda (obstacles),y
  and #%00110000
  clc
  ror
  ror
  ror
  ror
  tax ; X <- B5-B4 ~ health of obstacle.
  lda digits,x
  plx
  sta vram,x
  dey
  jmp blit_obstacle_done
blit_obstacle_is_off: ; always decrement Y once more.
  dey
blit_obstacle_done:
  dey
  bpl obstacles_blit_loop
blit_obstacles_done:


  ;; flip the vRAM on the LCD.

  ;> debug prints.
;  ldy #12
;  lda #charged_shot           ; blit charge
;  jsr blit8
;  ldy #14
;  lda player_charge           ; blit charge
;  jsr blit8
;
;  lda player_status           ; blit player status.
;  ldy #54
;  jsr blit8
;  lda missile_status
;  ldy #51
;  jsr blit8

;  lda prng_num                ; blit random comparison.
;  cmp #$04
;  bcs no_enemy
;enemy:
;  lda #$ff
;  ldy #47
;  sta vram,y
;no_enemy:
;debug_obstacles_blit:
;  lda #nb_obstacles   ; 2 bytes * nb_obstacles.
;  clc
;  adc #nb_obstacles
;  tay
;  ldx #10
;  dey
;debug_obstacles_blit_loop:
;  lda (obstacles),y   ; read the MS bits.
;  phy
;
;  phx
;  ply
;  jsr blit8
;  phy
;  plx
;  ply
;  phx
;
;  dey
;
;  lda (obstacles),y
;  phy
;  phx
;  ply
;  jsr blit8
;  phy
;  plx
;  ply
;  phx
;
;  dey
;  bpl debug_obstacles_blit_loop
  ; end of debug <

  jsr flip_vram

  jmp game_loop





unknown_error:
  lda #%00000010           ; go home.
  jsr lcd_instruction
  lda #<unknown_error_bg  ; print message.
  sta ptr16
  lda #>unknown_error_bg
  sta ptr16 + 1
  jsr print_string
unknown_error_loop:
  jmp unknown_error_loop


; template                 "                |                      |                "
menu_bg:           .asciiz " MENU of GLIDER |                      | options   play "
options_bg:        .asciiz " mode :         |                      |           back "
game_over_bg:      .asciiz "GAME OVER  menu |                      |PTS:        new "
unknown_error_bg:  .asciiz "    UNKNOWN     |                      |     ERROR      "
easy_mode_msg:     .asciiz " EASY "
normal_mode_msg:   .asciiz "NORMAL"
hard_mode_msg:     .asciiz " HARD "





;>>> empty_vram(): empty the vram buffer, replacing everything with " ".
;
; preconditions:  - none
; execution:      - none
; postconditions: - A (overwritten)
;                 - X (overwritten)
;                 - Y (preserved)
;<<<
empty_vram:
  lda #" "              ; empty vram.
  ldx #vram_size
empty_vram_loop:
  sta vram,x
  dex
  bpl empty_vram_loop
vram_empty:
  rts

;>>> fill_bg_vram(): fill the vRAM with a string. The string is treated as a background and
;                    and allows future blits on the vRAM.
;
; preconditions:  - word pointer to the background string in ptr16.
; execution:      - none
; postconditions: - A (overwritten)
;                 - X (preserved)
;                 - Y (overwritten)
;<<<
fill_bg_vram:
  ldy #0
fill_bg_vram_loop
  lda (ptr16),y
  beq fill_bg_vram_done
  sta vram,y
  iny
  jmp fill_bg_vram_loop
fill_bg_vram_done
  rts

;>>>flip_vram(): flip the vRAM onto the LCD screen. Allows the CPU to do computations in the
;                vRAM buffer, without changing the LCD state until flip time (avoid flickering).
;
; preconditions:  - none
; execution:      - 5 bytes pushed onto the stack ((2 +) 3 in lcd_instruction or print_char).
;                 - 5 bytes pulled onto the stack ((2 +) 3 in lcd_instruction or print_char).
; postconditions: - A (overwritten)
;                 - X (overwritten)
;                 - Y (preserved)
;<<<
flip_vram:
  lda #%00000010              ; go home.
  jsr lcd_instruction
  ldx #0                      ; flip vRAM.
flip_vram_loop:
  lda vram,x
  jsr print_char
  inx
  txa
  cmp #vram_size
  bne flip_vram_loop
  rts

;>>> print16_decimal(): print a word in decimal format.
;
; preconditions:  - word in div10 in RAM
; execution:      - 7 bytes pushed onto the stack ((2 +) 5 in print_string or (2 +) 1 in  push_char_to_message).
;                 - 7 bytes pushed onto the stack ((2 +) 5 in print_string or (2 +) 1 in  push_char_to_message).
; postconditions: - A (overwritten)
;                 - X (overwritten)
;                 - Y (overwritten)
;<<<
print16_decimal:
  lda #0       ; empty message.
  sta message
prt16divinit
  ; initialize the remainder modulo 10.
  lda #0
  sta mod10
  sta mod10 + 1
  clc

  ldx #16
prt16divloop:
  rol div10       ; rol the 4 bytes.
  rol div10 + 1
  rol mod10
  rol mod10 + 1

  sec             ; subtract 10 from remainder.
  lda mod10
  sbc #10
  tay
  lda mod10 + 1
  sbc #0          ; a,y = dividend - divisor.

  bcc prt16divskip
  sty mod10
  sta mod10 + 1

prt16divskip:
  dex
  bne prt16divloop

  rol div10         ; shift last bit from carry into div10.
  rol div10 + 1

  ; print the character on LCD.
  lda mod10
  clc
  adc #"0"
  jsr push_char_to_message

  ; continue algorithm until dividend is 0.
  lda div10
  ora div10 + 1
  bne prt16divinit

  ; complete with spaces.     WORK IN PROGRESS.
  ldx #0
  ldy #5
prt16countchrs:
  lda message,x
  beq prt16completestr
  inx
  dey
  jmp prt16countchrs
prt16completestr:
  tya
  beq prt16strcomplete
prt16completechr:
  lda #" "
  phy
  jsr push_char_to_message
  ply
  dey
  bne prt16completechr

prt16strcomplete:
  lda #<message
  sta ptr16
  lda #>message
  sta ptr16 + 1
  jsr print_string
  rts

;>>> push_char_to_message(): push a character onto 'message'.
;
; preconditions:  - 8-bit character in A.
; execution:      - 1 byte pushed onto the stack (1 in body).
;                 - 1 byte pulled onto the stack (1 in body).
; postconditions: - A (overwritten)
;                 - X (overwritten)
;                 - Y (overwritten).
;<<<
push_char_to_message:
  pha             ; new character onto stack.

  ldy #0
phcharloop:
  lda message,y   ; pull head of message into X.
  tax
  pla
  sta message,y   ; change current character.
  iny
  txa
  pha             ; push new character onto stack.
  bne phcharloop

  pla             ; put back the null terminating character.
  sta message,y
  rts

;>>> print_string(): print a string.
;
; preconditions:  - 16-bit string pointer in ptr16.
; execution:      - 5 bytes pushed onto the stack ((2 +) 3 in print_char).
;                 - 5 bytes pushed onto the stack ((2 +) 3 in print_char).
; postconditions: - A (overwritten)
;                 - X (preserved)
;                 - Y (overwritten)
;                 - ptr16 (overwritten if string is more than 256 chars).
;<<<
print_string:
  ldy #0           ; start at index 0.

prt_str_loop:
  lda (ptr16),y   ; load character.
  beq prt_str_end ; end if null character.

  jsr print_char

  iny             ; inc the low byte index.
  bne prt_str_loop
  inc ptr16+ 1    ; inc the high byte index.
  jmp prt_str_loop

prt_str_end:
  rts

;>>> irand(): initialize the pRNG with arbitrary values.
;
; preconditions:  - none
; execution:      - none
; postconditions: - pRNG initialized.
;                 - A (overwritten)
;                 - X (preserved)
;                 - Y (preserved)
;                 - RAM: writes at prng_mod, prng_mult and prng_inc.
;<<<
irand:
  lda #223
  sta prng_mod
  lda #111
  sta prng_mult
  lda #17
  sta prng_inc
  rts

;>>> srand(): initialize the pRNG's seed, i.e. the first number of the series.
;
; preconditions:  - 8-bit seed in A.
; execution:      - none
; postconditions: - pRNG's seed initialized.
;                 - A (preserved)
;                 - X (preserved)
;                 - Y (preserved)
;                 - RAM: writes at prng_seed and prng_num.
;<<<
srand:
  sta prng_seed
  sta prng_num
  rts

;>>> rand(): use the pRNG to generate the next pseudo-random number of the series.
;
; preconditions:  - none
; execution:      - 3 bytes pushed onto the stack ((2 +) 1 in divide8).
;                 - 3 bytes pulled onto the stack ((2 +) 1 in divide8).
; postconditions: - A (overwritten)
;                 - X (overwritten)
;                 - Y (overwritten)
;                 - RAM: - prng_num (new pseudo-random number)
;                        - writes at prng_mod, prng_mult and prng_inc.
;<<<
rand:
  lda prng_num       ; get previous number.

  ldx prng_mult      ; multiply it.
  dex ; one is superfluous.
  clc
rand_mult_loop:
  adc prng_num
  dex
  bne rand_mult_loop

  adc prng_inc       ; increment the number.

  tax                ; apply the modulo.
  ldy prng_mod
  jsr divide8

  stx prng_num       ; store new number.

  inc prng_mult      ; trick to change
  bne mess_with_inc  ; the parameters of
  lda #223           ; the pRNG.
  sta prng_mult
mess_with_inc:       ; simply increment them.
  inc prng_inc       ; make sure prng_mult and
  inc prng_mod       ; prng_mod are not zero.
  bne rand_end
  lda #111
  sta prng_mod
rand_end:
  rts

;>>> divide8(): computes the true division a / b.
;
; preconditions:  - a in X.
;                 - b in Y.
;                 - a >= b
;                 - a and b are bytes.
; execution:      - loop invariant: a = bq + r (a = b*Y + X)
;                 - 1 byte pushed onto the stack (1 in body).
;                 - 1 byte pulled onto the stack (1 in body).
; postconditions: - A (overwritten)
;                 - X (holds rest)
;                 - Y (holds quotient)
;<<<
divide8:
  phy             ; store b onto stack.
  ldy #0          ; r=a in X and q=0 in Y

div8loop:
  pla             ; pull b from stack.
  stx buffer8     ; put r in buffer8.
  cmp buffer8     ; compare r and b.
  bcs div8end
  pha             ; push b back onto stack.

  iny             ; increment q.

  sta buffer8     ; put b in buffer8.
  txa             ; put r in A.
  sec
  sbc buffer8     ; A <- r - b
  tax             ; put r back in X.

  jmp div8loop    ; go back to loop.

div8end:
  rts

;>>> blit8(): blit a byte onto vram.
;
; preconditions:  - byte in A.
;                 - vram address in Y.
; execution:      - 1 byte pushed onto the stack (1 in body).
;                 - 1 byte pulled onto the stack (1 in body).
; postconditions: - A (preserved)
;                 - X (overwritten)
;                 - Y (+2)
;<<<
blit8:
  pha
  ror             ; roll to get the 4 MS bits.
  ror
  ror
  ror
  and #%00001111  ; mask the other bits.
  tax             ; transfer the index in X.
  lda digits,x    ; print the character.
  sta vram,y
  iny
  pla             ; get back the argument.
  pha
  and #%00001111  ; mask the MS bits.
  tax             ; transfer index and print.
  lda digits,x
  sta vram,y
  pla             ; pull back A and X and return.
  iny             ; increment y to use the function in a row.
  rts

digits: .asciiz "0123456789abcdef"  ; the list of all possible hexadecimal digits.

;>>> lcd_wait(): wait for the LCD's busy flag to go low, indicating that the LCD is done.
;
; preconditions:  - none.
; execution:      - 1 byte pushed onto the stack (1 in body).
;                 - 1 byte pulled onto the stack (1 in body).
; postconditions: - A (preserved)
;                 - X (preserved)
;                 - Y (preserved)
;<<<
lcd_wait:
  pha               ; push A to retrieve it later.
  lda #%00000000    ; set port B as input.
  sta DDRB
lcd_busy_loop:
  lda #RW           ; set RW pin to read the LCD.
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB         ; read the LCD's status.
  and #%10000000    ; isolate busy flag, i.e. the MSB.
  bne lcd_busy_loop ; busy if flag is set.

  lda #RW           ; disable the LCD.
  sta PORTA
  lda #%11111111    ; set port B as output.
  sta DDRB
  pla               ; pull A and return.
  rts

;>>> lcd_instruction(): send an instruction to the LCD. wait for the device to be ready.
;                       see https://eater.net/datasheets/HD44780.pdf at Instructions (p.24) and Instruction and Display Correspondence (p.39) for more information about the instructions and how to use them.
;
; preconditions:  - 8-bit instruction in A.
; execution:      - 3 bytes pushed onto the stack ((2 +) 1 in lcd_wait).
;                 - 3 bytes pulled onto the stack ((2 +) 1 in lcd_wait).
; postconditions: - A (overwritten)
;                 - X (preserved)
;                 - Y (preserved)
;<<<
lcd_instruction:
  jsr lcd_wait    ; wait...
  sta PORTB
  lda #0          ; clear control bits.
  sta PORTA
  lda #E          ; set E bit to send instruction.
  sta PORTA
  lda #0          ; clear control bits.
  sta PORTA
  rts

;>>> print_char(): print a character on the LCD. wait for the device to be ready.
;                  see https://eater.net/datasheets/HD44780.pdf at Function Description (p.17-18) formore information about the LCD and available characters.
;
; preconditions:  - 8-bit character in A.
; execution:      - 3 bytes pushed onto the stack ((2 +) 1 in lcd_wait).
;                 - 3 bytes pulled onto the stack ((2 +) 1 in lcd_wait).
; postconditions: - A (overwritten)
;                 - X (preserved)
;                 - Y (preserved)
;<<<
print_char:
  jsr lcd_wait    ; wait...
  sta PORTB
  lda #RS         ; select data register.
  sta PORTA
  lda #(RS | E)   ; set E bit to send instruction
  sta PORTA
  lda #RS         ; disable LCD.
  sta PORTA
  rts





; the non-maskable interrupt pin is not connected here.
nmi:
; counter is incremented when an interrupt is triggered.
irq:
  pha              ; stash everything onto the stack.
  phx
  phy

exit_irq:
  bit PORTA        ; clear the interrupt.

  ply              ; restore CPU's internal state.
  plx
  pla
  rti





  .org $fffa
  .word nmi
  .word reset
  .word irq
