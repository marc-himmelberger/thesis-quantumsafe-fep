#!/bin/bash

# Ensure correct remote present
if ! git remote | grep -q latex; then
    git remote add -f latex https://git:olp_6CYA7UJ8bd3GebksBVNGiBJMKTXcDq3k144k@git.overleaf.com/6780e2bde2975c5d641bb05d
fi

# Preserve state, but not latex/ folder
push1=$(git stash push --keep-index --include-untracked -m "unstaged" -- ':!latex/')
push2=$(git stash push -m "staged" -- ':!latex/')

# Clean and check out last latex/ state
rm -rf latex/
git reset --hard

# Clone Overleaf
git pull --no-edit --squash -s subtree latex master
git commit -m "Merge Overleaf"

# Restore state
if [ "No local changes to save" != "$push1" ]; then
    git stash pop
    git add --all
fi
if [ "No local changes to save" != "$push2" ]; then
    git stash pop
fi
