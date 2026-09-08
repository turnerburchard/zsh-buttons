#!/usr/bin/env zsh

setopt errexit

typeset test_dir=${0:A:h}
zsh "$test_dir/ranking.zsh"
expect "$test_dir/interactive.exp"
