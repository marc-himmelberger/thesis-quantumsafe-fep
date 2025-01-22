#!/bin/bash

# Preserve state
push1=$(git stash push --keep-index --include-untracked -m "unstaged")
push2=$(git stash push -m "staged")

# Clone Overleaf
git pull --no-edit -s subtree latex master
git commit --amend -m "Merge Overleaf"

# Restore state
if [ "No local changes to save" != "$push1" ]; then
    git stash pop
    git add --all
fi
if [ "No local changes to save" != "$push2" ]; then
    git stash pop
fi
