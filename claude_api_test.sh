#!/bin/bash

# Corrected Claude API call using the Messages API
curl https://api.anthropic.com/v1/messages \
     --header "x-api-key: $ANTHROPIC_API_KEY" \
     --header "anthropic-version: 2023-06-01" \
     --header "content-type: application/json" \
     --data \
'{
    "model": "claude-3-sonnet-20240229",
    "max_tokens": 1024,
    "messages": [
        {
            "role": "user",
            "content": "Hello, Claude"
        }
    ]
}'
