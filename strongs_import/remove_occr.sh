#!/usr/bin/env bash
jq 'map(del(.occr))' strongs_dictionary.json > strongs_dictionary_nooccr.json
