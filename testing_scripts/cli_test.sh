#!/bin/bash

if [ ! -f ./main.lua ]; then
    cd ..
fi

if [ ! -f ./main.lua ]; then
    echo "Can'f find main.lua"
    exit
fi

#https://stackoverflow.com/questions/8937663/shell-script-to-check-whether-a-server-is-reachable
if nc -z localhost 9000 2>/dev/null; then
    echo "Server is up ✓"
else
    echo "Server isn't running. Exiting"
    exit
fi

echo -e "localhost:9000" > hashstore_client_config

small_file=test_files/funni.gif
big_file="test_files/big file.m4a"
repl_commands="testing_scripts/repl_commands"

list_before=$(luajit main.lua list)
count_before=$(echo $list_before | wc -l)
echo "Current number of files: $count_before"

echo "Uploading files..."
luajit main.lua upload -F $small_file
luajit main.lua upload -F "$big_file"

echo -e "\n----\n"

luajit main.lua list

echo -e "\n----\n"

echo "Uploading a file via pipe"
cat main.lua | luajit main.lua up -p "main test"

echo -e "\n----\n"

echo "Trying to pipe into repl:"
cat $repl_commands
echo -e "\n"
cat $repl_commands | luajit main.lua repl

echo -e "\n\n----\n"


list_after=$(luajit main.lua list)
count_after=$(echo $list_after | wc -l)
echo "Current number of files: $count_after"
if (( count_before == count_after )); then #https://stackoverflow.com/questions/18668556/how-can-i-compare-numbers-in-bash
    echo "Number of files stayed the same"
    if [ "$list_after" = "$list_before" ]; then #https://stackoverflow.com/questions/2237080/how-to-compare-strings-in-bash
        echo -e "List of files is the same as before (good) \nTest is done!"
    else
        echo "List has changed (bad)"
    fi
elif [[ $count_before -gt $count_after ]]; then
    echo "Lost $((count_before-count_after)) files (bad)" #https://stackoverflow.com/questions/59759172/could-you-explain-the-syntax-of-math-in-a-bash-shell
else
    echo "Gained $((count_after-count_before)) files (bad)"
fi
