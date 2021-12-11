from ./wavecorepkg/db import nil
from ./wavecorepkg/db/entities import nil
from ./wavecorepkg/db/db_sqlite import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/db/vfs import nil
from os import `/`
from osproc import nil
from ./wavecorepkg/ed25519 import nil
from ./wavecorepkg/paths import nil
from ./wavecorepkg/common import nil

const
  port = 3000
  asciiArt =
    """
                           ______                     
   _________        .---'''      '''---.              
  :______.-':      :  .--------------.  :             
  | ______  |      | :                : |             
  |:______B:|      | |   Welcome to   | |             
  |:______B:|      | |                | |             
  |:______B:|      | | ANSIWAVE   BBS | |             
  |         |      | |                | |             
  |:_____:  |      | |     Enjoy      | |             
  |    ==   |      | :   your stay    : |             
  |       O |      :  '--------------'  :             
  |       o |      :'---...______...---'              
  |       o |-._.-i___/'             \._              
  |'-.____o_|   '-.   '-...______...-'  `-._          
  :_________:      `.____________________   `-.___.-. 
                   .'.eeeeeeeeeeeeeeeeee.'.      :___:
                 .'.eeeeeeeeeeeeeeeeeeeeee.'.         
                :____________________________:
    """
  subboard1Text =
    """
                                       
                                    )  
    )            (       )  (    ( /(  
 ( /(   (     (  )\   ( /(  )(   )\()) 
 )(_))  )\ )  )\((_)  )(_))(()\ (_))/  
((_)_  _(_/( ((_)(_) ((_)_  ((_)| |_   
/ _` || ' \))(_-<| | / _` || '_||  _|  
\__,_||_||_| /__/|_| \__,_||_|   \__|  
                                       
    """
  subboard2Text =
    """
         _    ___                  _    
  __ _  (_)__/ (_) __ _  __ _____ (_)___
 /  ' \/ / _  / / /  ' \/ // (_-</ / __/
/_/_/_/_/\_,_/_/ /_/_/_/\_,_/___/_/\__/ 
                                        
    """
  jabba =
    """
[0m[40m                                                                                [0m
[0m[40m                                                        [33m▄▄▄[37m                     [0m
[0m[40m                                                     [33m▄[1;43;30m░░[31m░░░░░▒[40m▄▄[22;33m▄[37m               [0m
[0m[40m                                                   [1;30m▄[43m▒░[22;40;33m▀▀▀██[1;43;31m▒▓▓[22;40;33m▀▀[1;31m▀▀█▄[22;33m▄[37m           [0m
[0m[40m                                                 [1;30m▄▀▀[33m▄[22m [1;43;37m█[40;33m█[43m░[22;40m [1;43;30m░[22;40;33m█[1;43;31m░▓[22;40;33m █[1m█[22m [1;37m▄[33m▄[31m▀▀[43m▄[22;40;33m▄[37m        [0m
[0m[40m                                               [1;30m▄▀[22;33m ▀[1m▀▀[22m [1m▀[22m▄▄[1;43;30m▒[22;40;33m███[1;43;31m░▄[40m▄▄[22;33m▄ [1;37m▀[33m▀[22m▀ [1;43;31m▄[33m [22;40m▄[37m      [0m
[0m[40m                                            [1;30m▄▄████[43m▓▓▒▒▒[22;40;33m▀▀  [1;43;31m▀▀[22;40;33m█▄▄ ▀▀██[1;43;31m░░▒▓▄▄[22;40;33m▄▄[37m   [0m
[0m[40m                                          [1;30m░▒▓████[43m▓▓▓▒▒░░░[22;40;33m▀▀▀▀▀▀▀▀▀▀███[1;43;31m░▒▒▒▀▀▀[22;40;33m█▄[37m [0m
[0m[40m                                            [1;30m▀▀▀█████▀▀[22;33m ▄▄▄[1;43;30m░░░[31m▀▀[22;40;33m█▄▄▄▄ ▀▀██▀▀[37m     [0m
[0m[40m                                              [1;30m▀▄▄▄▄▄█[43m▓▓▒░░[22;40;33m█▀▀▀▀▀▀██[1;43;31m░░▒▒▓██▀▀[22;40;33m▀[37m   [0m
[0m[40m                                                 [1;30m▀▀▀███[43m▒▒[22;40;33m▄▄▄████▄▄███[1;43;31m░░░[22;40;33m█▀▀[37m     [0m
[0m[40m                                                       [1;30m▀▀[22;33m▀▀▀▀▀▀▀▀▀▀▀[37m            [0m
[0m[40m                      [32m▄▄▄▄▄▄[33m▄▄▄[37m                                                 [0m
[0m[40m                 [32m▄[1;42m▒▒░░[22;43m█▓▓▒▒░░[40;33m█▓▓▓▄▄[37m                                             [0m
[0m[40m               [32m▄[1;42m▄▓[22;40m█▀▀▀▀▀[43m▒░░░[40;33m█[1;43;37m░ [22;40;33m▀▀▀▀█▄[37m               [33m                      [37m      [0m
[0m[40m    [33m   [37m      [32m▄[1;42m▄[33m█[32m▀[22;40m▀[33m▄[1;37m▄[22;33m [1m█[43m░[22;40m  [1;43;32m▒░[22;40;33m█[1;43;37m ░[22;40;33m [41m▒[1;43m▓[40m█[43;37m█[22;40;33m ▀█▄[37m                                         [0m
[0m[40m           [32m▄[1;42m▄[33m▓[32m▀[22;40m█[33m █[1m█[37m▓[22;33m [1m▀[22m▀▄[1;43;32m░▒▒░[22;40;33m█[1;43;37m [22;40;33m█▄▄▀[1m▀[22m [1m▀[22m ██▄▄[37m                                      [0m
[0m[40m        [32m▄▄[1;42m▄▓▓▓░[22;40m▄▄[33m▄▄▄▄█▀▀▀▄[1;43;32m░░[22;40;33m██ ▀▀██████[1;43;30m░░▒▒▓[40m▄[22m                                   [0m
[0m[40m     [32m▄[1;42m▄▄█▓▓▒▒[22;43m█▓▒▒░░[40;33m█▀▄▄▄▄████▓▓▄▄▄▄███[1;43;30m░░▒▒▓▓[40m▀[22m                                   [0m
[0m[40m    [32m▐[1;42m▒[22;40m▄▀▀▀[1;42m░░[22;43m▓▓▒▒░░[40;33m██▀▀▀          ▀▀▀▀[1;43;30m░░░[40m▀▀▄▄[22m                                    [0m
[0m[40m     [32m█[1;42m▒▒░░[22;43m█[40;33m▄▄  ▀      [31m░░[1;30m                 ▄▄█[22m                                    [0m
[0m[40m      [32m▀█[1;42m░░[22;43m▓▓▒░░[40;33m▄▄           [31m▄▄▄▄[33m       [1;30m▄▄[43m▓▓[40m▌[22m                                    [0m
[0m[40m        [32m▀█[43m▓▓▒▒▒░░[40;33m██▄▄▄▄     [31m▀[1;41m▓▒▒[22;40m▌[33m  ▄██[1;43;30m▒▒▒▒[40m▀[22m                                     [0m
[0m[40m          [32m▀▀▓[43m░░░░░░[40;33m█▓███▓▓▓▒ [31m▐[1;41m░░[22;40m█[33m █[1;43;37m░[30m░░░[40m█▀[22m                                       [0m
[0m[40m              [33m▀▀██████▀▀██▓▓▒ [31m█[1;41m░[22;40m▀[33m ████▀[37m                                         [0m
[0m[40m                   [33m▀▀████▄▄▄▄█▄▄██▀[37m        [33mZII[37m                                  [0m
[0m[40m                        [33m▀▀▀▀▀▀▀░[37m                                                [0m
    """
  hogan =
    """
[0m[40;37m                                                                                [0m
[0m[40m  [31mHulk Hogan                           ▄▄██████████[1;41m▄[22;40m▄▄                          [0m
[0m[40m[37m  [1;30mWWE Hall of Fame 2005         [22m    [31m▄[1;41m▄░ [22;40m█████████████[1;41m▀▄[22;40m▄                        [0m
[0m[40m[37m                                   [31m▐[1;41m█▌ [22;40m█████████████[1;41m░░▓█[22;40m▌                       [0m
[0m[40m[37m                                   [31m▐[1;41m▓ [22;40m█████████████▓▓▀[1;41m▀▓[22;40m▌                       [0m
[0m[40m                                   █[1;41m░[22;40m██████████████████▄▀                       [0m
[0m[40m                                   █████████████████████▄▌                      [0m
[0m[40m                                  ▐█████████▓▓▓▓▓▓████[1;41m░░▓[22;40m▌                      [0m
[0m[40m                                  █▓[41;33m▄[1m▄▄[40m▄[37m▄▄[33m▄[22m▄[31m [1;33m▄[43m▄▄▀▀[40m▀▀▀█[41;37m▄[22;40;31m█[37m [31m▄                      [0m
[0m[40m                                  ▀[1;33m█▌[22m    [1;33m [22m▀[1m██▌      [22m▐[1m█▀[22m [31m█[1;41m░[22;40m▌                     [0m
[0m[40m                                 [33m▐▌▀[1m▒[22m▄[37m   [33m▄[1;43m▄▀[22;40m░[1m▓[22m▄[37m  [33m ▄[1;43m▄▀[22;40m▀▄[1m▓▄[22;31m▀▌                     [0m
[0m[40m                                 [33m▐▓[1;47;31m▀[22;40;33m▄▀▀[1m▀▀▀[22m▄[1;47;31m▓█[22;40;33m▄[1m▀▀[22m▓[1;43m▀[40m▀[22m▀▄[1;43;31m▄[47m░[22;40m▄ [33m▄                      [0m
[0m[40m                                  ▓[37m▐[1;47;31m▓[43m▀[47m▓▄[43m▀[22;40;33m▀[1;47;31m▓▀▓[43m█▀[22;40;33m▀[1;43;31m▀[47m▄▓[43m▀[22;40;33m▀[1;47;31m▓[33m░▓[22;40m▐▌[31m▄                     [0m
[0m[40m                                  [33m [37m▐[1;43;31m█[22;40;33m▌[1;43;31m▀[22;40;33m▀▄[1;31m░[22m [33m▀▀[37m [33m░▓▄▀[1;43;31m█[47m▓[22;40;33m▌[1;47;31m▓ [33m░[22;40m█[1m [41;31m░[22;40m▌                    [0m
[0m[40m                                  [33m▐[1;31m▐[43m▌[22;40;33m▐[1;43m▄[40m▓▓██[37m██████▓[43;33m▄[31m▓[40m▌[47m▓░▄[22;40;33m▌[1;37m░[22;31m▐▌                    [0m
[0m[40m                                  [1;33m▐[22m [33m█[1m▐██▀[22m▄[1;31m▄▄▄▄▄[22;33m▄[1m▀█[37m█[43;33m▌[31m▓[47m▓[43m▀[22;40;33m▄▌[1;37m▓[33m [22;31m▀                    [0m
[0m[40m                                  [1;37m▐[43;33m▄[40m █[37m██[22;33m▐[1;43;31m██[22;40;33m▄▄▄[1;43;31m▄█[22;40;33m▌[1m█[37m█▓[43;31m▓[47m█[22;40;33m▄[1;47;31m▀[22;40m [1m█[33m▐[22m [31mn!                  [0m
[0m[40m                                  [1;37m▐[33m█[22m▌[1;37m▓██[31m▐[47m▓▓▓[43m████[22;40;33m▌[1m█[37m██[43;31m▀[22;40;33m▀[1;47;31m▀░[40;33m▐[37m█[33m▐▌                    [0m
[0m[40m                                  [43m▐[40m█▌[22m [1m▀▐[22;33m▐[1;47;31m░░░[43m█[47m▀[43m██[22;40;33m▌[1m█▌▀[22m▄[1;47;31m▓░▒[40;33m▐██▌                    [0m
[0m[40m                                 [22m▐[1m▓▌▓[22m [33m▓[1;31m▄[22;33m▄▀[1;43;31m▀[47m▄[22;40;33m▐[1;43;31m▓▓[22;40;33m▓▀░░▓[1;43;31m █[47m▓▓[40;33m▐▀▀▓                    [0m
[0m[40m                                 [22m▀[37m [1;33m▌▀[22m [1;43;31m▄[47m [22;40;33m▓▓[1;31m▄[22;33m▄▄▄▄▄▓▓▓[1;43;31m  ▓▀[22;40;33m▀[37m▄██▄▄[1;33m▄▄[22m▄                [0m
[0m[40m                               [33m ▀[37m▄██[33m [1;43;31m▄[47m ▐[43m░[22;40;33m█[1;47;31m░[43m░░ ▓▄[22;40;33m█[1;43;31m░░░ [22;40;33m▀[37m▄[1;47;33m░░░▄▓▓[22;40m▀[33m▄▄▄[1m▀              [0m
[0m[40m                            [22m▄▄▀[37m▄███ [1;43;31m▄[47m░░▐[43m▓▓[47m▓[43m▓▓▓██▓▓▀[22;40;33m▀[37m▄[1;47;33m▓▓▓[40m██[47m▀[22;40m▀[33m▄██[1;43;31m▄▓▄[22;40;33m▄             [0m
[0m[40m                         ▄▓▓▀[37m▄█[1;47;33m░░[22;40m█▌[33m▐[1;47;31m▓▓▓█[43m██[47m█[43m█[47m▓▓[43m█▓▀[22;40;33m▀[37m▄[1;47;33m▄██[40m██[47m▀[22;40m▀[33m▄[1;43;31m▄▓▓░░[22;40;33m██▀▀            [0m
[0m[40m                       ▄[1;43;31m▄░[22;40;33m█ [1;47m░░░▓▓[22;40m█[1;33m [43;31m▀███[40m█[43m████▀[40m▀[22;33m▀[37m▄[1;33m▄[47m▄[40m████[47m▀[22;40m▀[33m▄[1;43;31m▄██▀[22;40;33m█[1;43;31m▄▄[22;40;33m▄[1;43;31m▓▀[22;40;33m▓▓▓▄         [0m
[0m[40m                     ▄[1;43;31m▄▓▓[22;40;33m█[37m [1;47;33m░▓▓▓[40m██[47m▓▄[22;40m▄[33m▀[1;31m▀▓▓▓▀[22;33m▀[37m▄[1;33m▄[47m▄[40m███████[47m▀[22;40m [1;43;31m▄▀▄█▄[40m█[47m██[40m███[43m▄░░[22;40;33m█[1;43;31m▀▄[22;40;33m▄       [0m
[0m[40m                    [1;43;31m▄[47m▀▀█[43m▀[22;40m [1;47;33m▄▐[40m█████████[47m▄[40m▄▄▄[47m▄[40m██████████[47m▀[22;40m [1;43;31m▄▓▓[47m▓▓[40m███████[47m▓[43m▓▓  ▐█▄[22;40m      [0m
[0m[40m                   [1;47;31m▀[33m▄[31m░▄[43m▀[22;40m [1;47;33m▄█[40;37m██[33m███████████████████████[22m▌[33m▐[1;43;31m▓[22;40;33m█[1;43;31m█[47m░░▀▓▓[40m█[47m███░▓[43m█▌ ▐[40m█[47m▓▓[22;40m     [0m
[0m[40m               [1;31m   ▓[47m▓▓█[43m▀[22;40m [1;47;33m▄[40;37m████[33m█████████████████████[47m▓[40m█[22m [1;43;31m▓░[22;40;33m█[1;43;31m▐[40m█[47m▄[33m░▄[31m ▀███░▓[43m█▌░[40m██[47m░░▀[22;40m    [0m
[0m[40m              [1;31m   [22;33m▐▀[1;47;31m██[43m▀[22;40;33m░[37m▐[1;33m█[37m████[33m█████████████████████[47m░[40m█[22m [1;43;31m░[22;40;33m█▐[1;43;31m ▀▓▓[47m▄░░▓█[40m█[47m▓[43m█▓[22;40;33m█[1;43;31m▓[40m█[47m▓[22;40m█[1;47;33m░░[22;40m    [0m
[0m[40m             [1;31m    [22;33m▄[1;43;31m▄[47m█[43m░[22;40;33m▓[37m [1;47;33m▐▓[40;37m███[33m██████████████████████[47m▐▓[22;40m▌[33m▐▌▐[1;43;31m  ░░▀[47m▓▓▓█[40m██[43m▀[22;40;33m█[1;43;31m▐[40m██[47m░[22;40m█[1;47;33m▓▓[40;31m▌   [0m
[0m[40m               [22;33m▄[1;43;31m▄[47m██[43m░ [22;40;33m▓[37m [1;47;33m▓▒[40m████████[41m▀[40m█████████████████[47m░▀[22;40m [33m▓ ▀▓[1;43;31m  ▀▓[40m████[43m▌[22;40;33m██[1;43;31m▓[40m██[22m██[1;47;33m▒▒[22;40m▌   [0m
[0m[40m           [1;31m  [22;33m▄[1;43;31m▄[40m███[43m░░░ [22;40m [1;47;33m░░[41m▌▐▀▀[40m█[41m▀░▀█▀█▀▀[40m█[41m▀[40m█[41m▀[40m█[41m█[40m███████[47m▌[22;40m█[1;47;33m [40m [22m▓ ▄█[1;43;31m  ▐[47m▓▓█[40m█[43m▓▄[22;40;33m█[1;43;31m▓▓[40m█[47m░[22;40m█[1;47;33m░░[40;31m▌   [0m
[0m[40m            [43m▄[47m▀[40m██[43m▓▓▓▓░ [22;40;33m▌[37m▐█[1;41;33m▌▐ ░▄▌▀ ▌ ▀ ▐ ▌▐ ▐ █ [40m█[41m▀ ▐[40m██[47m░░[22;40m▀[33m▄█[1;43;31m░░░▄[40m███[47m█[40m█[43m▓░[22;40;33m█[1;43;31m░▒[40m█[47m▓[22;40m███    [0m
[0m[40m        [1;31m   [43m▄[47m▓[40m██[43m██[47m▀▄[43m█▓▌[22;40;33m▓[1m [22m█[1;47;33m▐[40m█[41m ▄▀ ▐ ▌▐░ ▌░ ▌▐ ░▌▐ ▀ [40m██[47m▀[22;40m█[31m [33m▓[1;43;31m▄▓▓▓▓[40m████[43m█▓░[22;40;33m██▓[1;43;31m░[40m██[22m█[1;47;33m░[31m▐[22;40m    [0m
[0m[40m       [1;31m   [43m▄[47m▀[40m███[43m█[47m▌▓[43m██░▓[22;40;33m▌[1m▐[47m▄[30m▓[41;33m▀▀█[40m█[41m▄▀[40m█[41m▄[40m█[41m▌▐▄[40m█[41m▐▌[40m█[41m▌▐░▌▐▌▐[40m█[47m░[22;40m█▌[33m▐[1;43;31m██[47m▓▓█[40m█████[43m██▓░[22;40;33m█▓▓[1;31m██[22m█[1;47;33m▒[22;40m▌    [0m
[0m[40m      [1;31m   [22;33m█▀[1;43;31m▀▄[40m█[47m█▓░▄[43m██ ░[22;40m [1;47;33m▐[40m█[47m▌[40m█████[41m█[40m███████████████[41m░[40m█[47m▌[22;40m██ [1;43;31m▓█[47m░░░▓▓[40m█████[47m▓▓[43m▓░[22;40;33m▓[1;43;31m░[40m█[47m▌[33m░▓[40;31m▌    [0m
[0m[40m         [22;33m▄[1;43;31m▄[40m██[47m▌▄█[43m█▓█▌[22;40;33m▓[1;43;31m [22;40m [1;47;33m▐[40m█████████████████████████[47m░[22;40m█▌[33m▐[1;31m█[22m██[1;47;33m  [31m░░▌▌[40m███[43m█[47m▓[43m█▓[22;40;33m█[1;43;31m▓[40m█[47m▌[33m░░[22;40m     [0m
[0m[40m    [1;31m   [22;33m▄[43;37m▄[1;40;31m███[43m▓▓▓█▓░█▌[22;40;33m▓▓[37m [1;33m█████████████████████████[47m▌[22;40m██▌[1;31m▐█[22m█[1;47;31m▌[33m▌▓▐[31m ▌▌[40m███[43m████[22;40;33m█[1;43;31m▐[40m█[47m░[22;40m█[1;47;31m▐[22;40m     [0m
[0m[40m    [1;31m  [22;43m▄[1;47;31m█[40m███[43m▓░░░▀░[22;40;33m█[1;43;31m▓[22;40;33m█▓▓[37m [1;33m██████████████████████[37m██[33m█[47m▌[22;40m██▌[33m▐[1;43;31m▓[40m█[47m▌[33m░░░[31m  ▌[40m███[43m████[22;40;33m█[1;43;31m▐[47m█[22;40m█[1;47;33m░[40;31m▌     [0m
[0m[40m     [43m▄[47m█[40m██[43m█▓░[22;40;33m [1;31m▄▄[22;33m▄▀▀[1;43;31m░░[22;40;33m▀[37m  [1;33m███████████████████████[47m▓▓▄▄[22;40m██[1;31m [43m░[40m██[47m▄ ░░▄[40m███[43m██[47m▓▓[43m▓[22;40;33m█[1;31m█[47m▓[22;40m█[1;47;31m▄[22;40m      [0m
[0m[40m    [1;47;31m▀░[43m████▀[22;40;33m▀[37m [1;43;31m▀[47m▄▓[43m▓▄[22;40;33m▄[37m    [1;33m████████████████████[47m▀▀[22;40m███████▌[33m▐[1;43;31m▀[40m███[47m▓▓[40m████[43m██[47m▓[43m█▌▐[40m█[47m░▄[22;40m       [0m
[0m[40m   ▐[1;47;33m▓[22;40m█[1;47;31m▓[43m▀[22;40;33m▀▄[1;31m▄[47m▀[43m▄[22;40;33m▄▀▀▓[1;43;31m▀[22;40;33m█[1;31m█[22;33m▄[1;31m▄▄[22;33m▄[1m▀████████████████[47m▄[40m████[47m▓▓░░[22;40m███[1;31m [43m ▀[40m████████[43m█▌█▓[22;40;33m▓[1;31m█[47m▓▄[22;40m        [0m
[0m[40m    [33m▀[37m▀ [33m▄[1;43;31m▄[47m▀▓▓[40m█[43m▀░▓▄[22;40;33m▄▓█[1;31m▌[43m▐[47m▓[43m█[22;40;33m▌[1m▐███████████████████[47m▀▀[40m▀[22m▀▀▀▀ [1;43;31m░░▓▓[40m██████[43m██ ▓ [40m█[47m▓▄[22;40m         [0m
[0m[40m  [33m ▄▐[1;31m█[22;33m▄▀[1;43;31m▓▓[22;40;33m▄▀[1;31m██[22;33m▄▀[1;43;31m▓▓[22;40;33m▄▓[1;31m█▄▀[22m [1;33m▄██████████████[47m▀▀[40m▀▀▀[22m▄▄[1;31m▄[43m▄▄[40m████████[47m▓▓[40m███[43m██▌[22;40;33m▓[1;43;31m░[40m▐[47m▓▄[22;40m          [0m
[0m[40m  [33m▐[1;47;31m▓[40m▄[22;33m▀[1;47;31m▓[43m▄[22;40;33m▄[1;43;31m▓[47m▓[22;40;33m▄▀[1;43;31m▀[47m▓[22;40;33m▄▀[1;43;31m▄▓[22;40;33m▄▓[1;31m██[22m [1;33m▄[37m▄▄▄[33m▄[22m [37m▀▀▀[1;33m▀▀▀▀▀[22m▄▄[1;31m▄[43m▄▄[40m███████[47m▓▓▓▀▀▄[40m██[43m▓▓▓[40m█[43m▀░[22;40;33m█[1;43;31m░[22;40;33m▌[1;31m█[47m▄[22;40m           [0m
[0m[40m   [33m▀[1;43;31m▀[22m▄[40;33m▄[1;31m▀[22;33m▀▀[1;43;31m▀[40m█[43m▄[22;40m [1;43;31m▀[40m█[22;33m▄▀[1;43;31m▀[40m▓[22;33m [1;47;31m▓▓[22;40;33m▌[1m▐████▐█▌[22m▓[1;43;31m░▓[40m██████[47m███▀▀▀▓▓▓▄▄▄[40m███[43m▓▓░░[22;40;33m██[1;43;31m▓▓[22;40;33m▌[1;43;31m▓[40m▐[47m▄[22;40m            [0m
[0m[40m   [33m█▄▀[1;31m▀▀[22;33m▀░░▀[1;31m▓▓[22;33m▄▀[1;31m▓▓[22m [33m░▓[1;43;31m▓█[22;40;33m▌[1m▐██████▌[31m▐██[47m▓▓▓▓▓▄▄▓▄▄▄▄[40m███[43m▓▓▓▓▓░░░[22;40;33m█▀█[1;43;31m▄█▓[22;40;33m▐[1;31m█[47m▓[22;40m             [0m
[0m[40m   [33m [1;31m▒▀▓███[43m▄▄[40m▄▄[22;33m▄[1;31m▓[22;33m▄▄▓[1;43;31m▐▐▐▀[40;33m ███████▌[31m▐[43m▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░[22;40;33m▀▀▄█[1;43;31m▄▓██ [40m █              [0m
[0m[40m[22m    [33m ▀▄[1;31m▓▓█[47m▓▓[40m█[43m▓▓▀▀[22;40;33m█[1;43;31m▀[22;40;33m█[1;43;31m▐▐[22;40;33m▌[1m▐████[47m▓▓▓[22;40m [33m▐[1;43;31m░░░░░░░░░░░    [22;40;33m▀▀▓▓▄▄█[1;43;31m▄▄▓▓[40m█[43m██▀[22;40;33m [1;31m█               [0m
[0m[40m     [22;33m [37m   [33m ▀▀[1;31m▀[43m▀▀▓▓▓░░[22;40;33m██[1m [47m▓▓▓[40m█[22m░[1;47;33m░░░[22;40m [33m▓▓▓▓███[1;43;31m     ▀▀▀ ▄▄▄▓▓▓▓██████[40m▓[22;33m ▀                [0m
[0m[40m        [1;30m▄        [22;33m▀▀▀▀[1m [47m ░░░[22;40m▓▐[1;47;33m  [22;40m▌[33m░▓[1;43;31m░░▒▒▓▓█████▓▓▓▓▓▓▓█████[40m▓▓▀▀[22;33m▀ [1;37m▄                 [0m
[0m[40m        [22m▐[1;47;33m▄     ▄[22;40m█          ▀▀▀[31m ▄▄▄▄▄[33m▀▀▀█[1;43;31m▀▀▀▀▀▀▀[22;40;33m██▀▀▀▀▀[31m▄▄▄▄[1;41;37m░▒▓██[22;40m                 [0m
[0m[40m         [1;47;33m▓[22;40m▌   [1;30m▐[47;33m▓[22;40m▌        [31m█████████████▄▄▄▄▄▄▄[1;37m    [22;31m█[1;41m░▓██▓▒░[22;40m█[1;41;37m░▒▓██[22;40m                 [0m
[0m[40m         [1;47;33m░[22;40m▌   ▐[1;47;33m░         [22;40;31m▀▀▓▓▓▓▓▓▓▓▓▓▓▓▀▀▀▓▓▓[37m [1;47;33m▄[22;40m▌ [31m▓▓[1m▓▓▓▓▓[22m▓▓▓[1;37m▓▓▓▓                 [0m
[0m[40m         [47;30m▌[22;40m▌   [1;47;30m▌[22;40m▌      ▐[1;47;33m█     [22;40;31m▒▒▒▒▒▒▒▒▒▒[37m ▄ [31m░░░[37m [1;47;33m▓[22;40m▌        [31m░░░[1;37m░░░░                 [0m
[0m[40m         [47;30m▌[22;40m▌   [1;47;33m░[22;40m▌      [1;47;30m▌[33m▓[22;40m █▄  [31m░░░░░░░░░░[37m [1;47;33m▓     ▒[40;30m▌[22m  ▄▄[1;30m▄                           [0m
[0m[40m         [22m▐[1;47;30m▐[22;40m   [1;47;33m▓[40;30m▌      [22m▐[1;47;33m░[40;30m▐[47;33m▓[22;40m▌             [1;47;33m▒[22;40m▌    [1;47;33m░[22;40m ▄█[1;47;30m▄[22;40m █[1;30m▌[22m▄█[1;47;30m▀[22;40m    [1;30m▄                  [0m
[0m[40m         [22m▐[1;47;30m▐[22;40m   [1;47;33m░[22;40m ▄[1;47;33m░[22;40m▄█[1;30m▄[22m ▐▌▐[1;47;33m░              ░[22;40m▌    ██▀[1;47;33m░▓[40;30m▄[22m█▐[1;47;33m░[22;40m▄    █[1;47;33m▄ [22;40m [1;30m▄[22m▄▄[1;30m▄[22m [1;30m▄[22m▄▄        [0m
[0m[40m         ▐[1;47;33m░[22;40m   ██▀[1;47;30m▄[22;40m█▀█[1;47;30m▀[22;40m█▌▐[1;47;30m▐[22;40m [1;47;30m▀[22;40m█     [1;30m▄[22m▄▄   [1;47;30m▌▐[22;40m  ▄█[1;47;33m░[22;40m  ▀██▀ [1;30m▀[47m▄[22;40m█  ▐[1;47;33m▓[30m▄[33m░░[22;40m█[1;47;30m▄[22;40m▀▀▀[1;30m▀          [0m
[0m[40m         ▐[47;33m░[22;40m  █[1;47;33m░      [22;40m▀[1;47;30m▌[22;40m▌▐[1;47;30m▐[22;40m▐[1;47;33m░[22;40m  [1;30m▄[22m▄[1;47;30m▀▄[22;40m▀[1;30m▀[22m    ▐[1;47;33m░[22;40m █▀ █        [1;30m▐[22m█▌ [1;47;33m░░[22;40m █                 [0m
[0m[40m          █   [1;47;33m░       [22;40m▐▌[1;30m▐[22m█ [1;47;30m▄[22;40m██[1;47;30m▄[40m▀        [22m▐█    █        ▐█  [1;30m▀                    [0m
[0m[40m         [22m▐█   █       [1;30m▐[22m█ █              [1;30m▐[22m█▌   █[1;30m▌       [22m█▌                       [0m
[0m[40m          █[1;30m▌[22m  █[1;30m▌       [22m█  ▀              [1;47;30m▄[22;40m▌   █[1;30m▌      [22m▐█                        [0m
[0m[40m          [1;30m▀[22m▀  ▐▌       ▐▌                     █▌      █▌                        [0m
[0m[40m               ▀        █                     █▌     ▐█[1;30m▌                        [0m
[0m[40m                                              [22m▀       ▀                         [0m
[0m[40m→SAUCE00hulk smash                         nail                blocktronics     [0m
[0m[40m   20200204½*  ☺☺P C      ¶IBM VGA                                              [0m
[0m
    """
  fabulous =
    """
 |  ___/ \  | __ )| | | | |   / _ \| | | / ___| 
 | |_ / _ \ |  _ \| | | | |  | | | | | | \___ \ 
 |  _/ ___ \| |_) | |_| | |__| |_| | |_| |___) |
 |_|/_/   \_\____/ \___/|_____\___/ \___/|____/ 
                                                
    """
  aerith =
    """
Aerith's theme

/instrument organ
/tempo 74
/play /8 d-,a-,e,f# a /2 f#,d+ /8 e-,e,c+ a /2 c,e /8 d-,a-,e,f# a d+ c#+ e+ d+ b c#+ /2 e-,c,a /2 c,e
    """
  staticFileDir = "bbs"

let
  sysopKeys = block:
    let path = "privkey"
    if os.fileExists(path):
      echo "Using existing sysop key"
      let privKeyStr = readFile(path)
      var privKey: ed25519.PrivateKey
      copyMem(privKey.addr, privKeyStr[0].unsafeAddr, privKeyStr.len)
      ed25519.initKeyPair(privkey)
    else:
      echo "Creating new sysop key"
      let keys = ed25519.initKeyPair()
      writeFile(path, keys.private)
      keys

assert paths.sysopPublicKey == paths.encode(sysopKeys.public)

when isMainModule:
  vfs.register()
  var s = server.initServer("localhost", port, staticFileDir)
  server.start(s)
  # create test db
  discard osproc.execProcess("rm -r " & staticFileDir / paths.boardsDir)
  os.createDir(staticFileDir / paths.boardsDir / paths.sysopPublicKey / paths.gitDir / paths.ansiwavesDir)
  os.createDir(staticFileDir / paths.boardsDir / paths.sysopPublicKey / paths.gitDir / paths.dbDir)
  db.withOpen(conn, staticFileDir / paths.db(paths.sysopPublicKey), false):
    db.init(conn)
  let sysop = entities.User(public_key: paths.sysopPublicKey)
  server.editPost(s, paths.sysopPublicKey, entities.initContent(common.signWithHeaders(sysopKeys, asciiArt, sysop.public_key, common.Edit), sysop.public_key), sysop.public_key)
  let
    subboard = entities.Post(parent: sysop.public_key, public_key: sysop.public_key, content: entities.initContent(common.signWithHeaders(sysopKeys, subboard1Text, sysop.public_key, common.New)))
    subboard2 = entities.Post(parent: sysop.public_key, public_key: sysop.public_key, content: entities.initContent(common.signWithHeaders(sysopKeys, subboard2Text, sysop.public_key, common.New)))
  server.insertPost(s, paths.sysopPublicKey, subboard)
  server.insertPost(s, paths.sysopPublicKey, subboard2)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = entities.User(public_key: paths.encode(aliceKeys.public))
    bob = entities.User(public_key: paths.encode(bobKeys.public))
  server.editPost(s, paths.sysopPublicKey, entities.initContent(common.signWithHeaders(aliceKeys, "Hi i'm alice", alice.public_key, common.Edit), alice.public_key), alice.public_key)
  server.editPost(s, paths.sysopPublicKey, entities.initContent(common.signWithHeaders(bobKeys, "Hi i'm bob", bob.public_key, common.Edit), bob.public_key), bob.public_key)
  let p1 = entities.Post(parent: subboard2.content.sig, public_key: bob.public_key, content: entities.initContent(common.signWithHeaders(bobKeys, aerith, subboard2.content.sig, common.New)))
  server.insertPost(s, paths.sysopPublicKey, p1)
  let p2 = entities.Post(parent: subboard.content.sig, public_key: bob.public_key, content: entities.initContent(common.signWithHeaders(bobKeys, jabba, subboard.content.sig, common.New)))
  server.insertPost(s, paths.sysopPublicKey, p2)
  let p3 = entities.Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(common.signWithHeaders(aliceKeys, "That ansi is\n" & fabulous, p2.content.sig, common.New)))
  server.insertPost(s, paths.sysopPublicKey, p3)
  let p4 = entities.Post(parent: p2.content.sig, public_key: sysop.public_key, content: entities.initContent(common.signWithHeaders(sysopKeys, "The people demand more jabba", p2.content.sig, common.New)))
  server.insertPost(s, paths.sysopPublicKey, p4)
  let p5 = entities.Post(parent: subboard.content.sig, public_key: bob.public_key, content: entities.initContent(common.signWithHeaders(bobKeys, hogan, subboard.content.sig, common.New)))
  server.insertPost(s, paths.sysopPublicKey, p5)
  server.insertPost(s, paths.sysopPublicKey, entities.Post(parent: p5.content.sig, public_key: alice.public_key, content: entities.initContent(common.signWithHeaders(aliceKeys, "I love hogan", p2.content.sig, common.New))))
  server.insertPost(s, paths.sysopPublicKey, entities.Post(parent: p5.content.sig, public_key: alice.public_key, content: entities.initContent(common.signWithHeaders(aliceKeys, "The navajo teepees i mean", p5.content.sig, common.New))))
  server.insertPost(s, paths.sysopPublicKey, entities.Post(parent: p5.content.sig, public_key: alice.public_key, content: entities.initContent(common.signWithHeaders(aliceKeys, "Acknowledge me plz", p5.content.sig, common.New))))
  discard readLine(stdin)
  server.stop(s)

