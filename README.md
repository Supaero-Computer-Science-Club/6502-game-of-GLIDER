# The game of Glider.
In this small directory, one will find all the material to run and understand the project of Glider. Glider is a simple 2D game running in the 2x16 LCD monitor coming with the 6502 kit from [here](https://eater.net/6502).  
In case of any issue, please open an issue on the repo or contact as at `supaerocsclub@gmail.com`.


## Table Of Content.
- [1  ](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#1-the-hardware-toc                               ) The Hardware.
- [2  ](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#2-the-software-technical-details-toc             ) The software: technical details.
- [2.1](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#21-objects-binary-representations-toc            ) Objects binary representations.
- [2.2](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#22-obstacles-array-structure-toc                 ) Obstacles array sructure.
- [3  ](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#3-run-the-code-toc                               ) Run the code.

## 1 The Hardware. [[toc](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#table-of-content)]
The overall schematics is very similar to the original one.  
A major additional feature is the debouncer circuit and all the buttons that are fully connected on the breadboards.  
| ![glider-schematics.png](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/blob/main/res/glider-schematics.png) | 
|:--:| 
| *Adaptation of the original design of Ben's 6502* |

| ![glider-debouncer-schematics.png](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/blob/main/res/glider-debouncer-schematics.png) | 
|:--:| 
| *The Debouncer Circuit* |

Note that the order of the buttons matter. They are connected, through the debouncer, to the 65C22 Versatile Interface Adapter (VIA) in the following order, from LSB to MSB:  
- `PA0`: the left button.
- `PA1`: the up button.
- `PA2`: the right button.
- `PA3`: the down button.
- `PA4`: the select button.  
 
such that, on the breadboards, it looks like:
```
PA0 PA1 PA2 PA3       PA4
 ^   ^   ^   ^         ^ 
 |   |   |   |         | 
 |  up   |   |         | 
left  right  .       select
   down     /
     \     /
      °---°
```

## 2 The software: technical details. [[toc](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#table-of-content)]
The code is commented and documented. If any part of the code is not clear, and it is likely to be so, please contact me or create issues on the github page. 

Below, one can find some details about the implementation.
### 2.1 Objects binary representations. [[toc](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#table-of-content)]
In the below table, one can find details about the binary representations of all the objects in the game.

```
bits              |  7|  6|  5|  4|  3|  2|  1|  0|                      explainations.
------------------+---+---+---+---+---+---+---+---+------------------------------------------------------------
player_status     |off|  y|rdy|can|HP3|HP2|HP1|HP0|  HP ~ the Health Points of the player.
------------------+---+---+---+---+---+---+---+---+------------------------------------------------------------
missile_status    |  y|off| P3| P2| P1| P0| B1| B0|  P ~ the position, B ~ the position buffer.
------------------+---+---+---+---+---+---+---+---+------------------------------------------------------------
(obstacles),y     | B7| B6| B5| B4| B3| B2| B1| B0|  B ~ the position buffer.
(obstacles),y + 1 | on|  y|HP1|HP0| P3| P2| P1| P0|  HP ~ the Health Points, P ~ the position.
------------------+---+---+---+---+---+---+---+---+------------------------------------------------------------
game_state        |GM1|GM0| B1| B0| S3| S2| S1| S0|  GM ~ the gamemode, B ~ the selected button, S ~ the state.
```

### 2.2 Obstacles array structure. [[toc](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#table-of-content)]
There are multiple obstacles, in the game, that glide from the right of the screen to the left, where the player is.  
There are stored in an array-like structure with following convention:
```
ob1|ob2|ob3|ob4|...|   obn   |
0 1|2 3|4 5|6 7|...|2n-2 2n-1|
```

## 3 Run the code. [[toc](https://github.com/Supaero-Computer-Science-Club/6502-game-of-GLIDER/tree/main/#table-of-content)]

To run the code, simply run `make`. This will assemble the source, show the byte-code and upload it to an eePROM through a TL866-like eePROM programmer.
