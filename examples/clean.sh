#!/usr/bin/env bash

find . -d 1 -type f -not -name "*.tr" -not -name "*.sh" -exec rm {} \;
