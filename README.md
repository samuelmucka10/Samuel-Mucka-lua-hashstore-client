Napísal som client pre hashstore server v podobe lua knižnice, ktorú som potom použil na vytvorenie CLI podľa zadania.<br>
Trochu som sa s tým pohral a pridal som pár iných príkazov.

Dúfam že som zadanie dobre pohopil :)

## Dependencies
- [lua](https://lua.org/)/[luaJIT](https://luajit.org/)
- [lua-socket](https://lunarmodules.github.io/luasocket/)
- [sha2.lua](https://github.com/Egor-Skriptunoff/pure_lua_SHA/tree/master)

## Inštalácia LuaJIT a luasocket na Fedore
Stačí nainštalovať Lua/LuaJIT a lua-socket: 
```bash
sudo dnf install luajit lua-socket
```
Na iných distribúciach by packagy mali byť podobné, ak nie rovnaké.

### Prečo LuaJIT
Program by mal fungovať na všetkých Lua verziach, ale LuaJIT je narýchlejší. Z môjho merania, pri výpočte hashu veľkého súboru s sha2.lua je LuaJIT aspoň 24x rýchlejší než Lua 5.4 interpreter.

## Použitie CLI
```bash
luajit main.lua <PRÍKAZ> <ARGUMENTY...>
```
### Základné CLI príkazy
```
list
get <hash>
upload <file path> <name>
delete <hash>
help
```

