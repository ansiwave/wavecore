from ./wavecorepkg/db import nil
from ./wavecorepkg/db/entities import nil
from ./wavecorepkg/db/db_sqlite import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/db/vfs import nil
from os import joinPath
from osproc import nil
from ./wavecorepkg/ed25519 import nil

const
  port = 3000
  address = "http://localhost:" & $port

const
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
  loremIpsum =
    """
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.
    """

let
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(server.dbFilename)

when isMainModule:
  vfs.register()
  var s = server.initServer("localhost", port, staticFileDir)
  server.start(s)
  # create test db
  discard osproc.execProcess("rm " & dbPath & "*")
  discard osproc.execProcess("rm " & staticFileDir.joinPath("ansiwaves") & "/*")
  var conn = db.open(dbPath)
  db.init(conn)
  db_sqlite.close(conn)
  let
    sysopKeys = ed25519.initKeyPair()
    sysop = entities.User(public_key: entities.initPublicKey(sysopKeys.public))
  server.insertUser(s, sysop)
  var p1 = entities.Post(public_key: sysop.public_key.base58, content: entities.initContent(sysopKeys, asciiArt))
  p1.content.sig.base58 = "root" # FIXME: this is just temporary
  server.insertPost(s, p1)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = entities.User(public_key: entities.initPublicKey(aliceKeys.public))
    bob = entities.User(public_key: entities.initPublicKey(bobKeys.public))
  server.insertUser(s, alice)
  server.insertUser(s, bob)
  let p2 = entities.Post(parent: p1.content.sig.base58, public_key: bob.public_key.base58, content: entities.initContent(bobKeys, "Hello, world...this is a lame comment\n\n" & loremIpsum))
  server.insertPost(s, p2)
  let p3 = entities.Post(parent: p1.content.sig.base58, public_key: bob.public_key.base58, content: entities.initContent(bobKeys, jabba))
  server.insertPost(s, p3)
  let p4 = entities.Post(parent: p3.content.sig.base58, public_key: alice.public_key.base58, content: entities.initContent(aliceKeys, "That ansi is\n" & fabulous))
  server.insertPost(s, p4)
  let p5 = entities.Post(parent: p3.content.sig.base58, public_key: alice.public_key.base58, content: entities.initContent(aliceKeys, "The people want more"))
  server.insertPost(s, p5)
  let p6 = entities.Post(parent: p1.content.sig.base58, public_key: bob.public_key.base58, content: entities.initContent(bobKeys, hogan))
  server.insertPost(s, p6)
  discard readLine(stdin)
  server.stop(s)
