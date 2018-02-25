#!/bin/bash

while read line
do
  if (( ${#line} > 120 ))
  then
    echo "$line"
  fi
done < <(strings libclassboxSDK.so)
