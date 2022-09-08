#!/bin/bash

activeMode=true

ACCOUNT_ID="zetsi.shardnet.near"
telegram_bot_token="5635727001:AAHozRmlx1gAJW1lwnP-GrgLFIcXLYTOJXM"
telegram_chat_id="-797143639"

mainUrl=https://rpc.shardnet.near.org
additionalUrl=https://rpc.shardnet.near.org

network="shardnet"
export NODE_ENV=$network
export PATH="/home/near/.cargo/bin:/home/near/.nvm/versions/node/v12.0.0/bin:$PATH"
export HOME="/home/near"
misslimit=1
missChunk=95
sleep1=60s
step_before_additional_check=10

# howTimeCanBlockProducedZero=3
messageResendCount=3

notDebug=true

if $notDebug; then 
    Title="Near"
    Message="Script for monitoring started"

    curl -s \
	    --data parse_mode=HTML \
	    --data chat_id=${telegram_chat_id} \
	    --data text="<b>${Title}</b>%0A${Message}" \
	    --request POST https://api.telegram.org/bot${telegram_bot_token}/sendMessage
fi

# status init
old_status_validator=""
old_block_height="Unknown"
old_status_block_height=""
old_status_block_not_produced=""
old_status_have_not_data=""
old_status_syncing=""
old_status_chunk=true
prev_epoch=0
need_send_message_at_next_step=false
step_additional=11
chunks_prev=-1

while true; do

    new_status_validator="Unknown"
    new_block_height="Unknown"
    new_status_block_height="Unknown"
    new_status_block_not_produced="Unknown"
    new_status_have_not_data="Unknown"
    new_status_syncing="Unknown"
    new_status_chunk=true

    expected_blocks="Unknown"
    produced_blocks="Unknown"

    messageBlockHeight="⚠️ Block Height: Unknown"
    messageSyncing="⚠️ Is Syncing: Unknown"
    messageEpoch="⚠️ Epoch: Unknown"
    messageValidator="⚠️ Validator: Unknown"
    messageDataPresent="⚠️ Data Validator: Empty"
    messageBlockProduced="⚠️ Blocks expected/produced: Unknown"
    messageAdditional="⚠️ Chunks: Unknown"

    VALIDATOR=`curl -s http://127.0.0.1:3030/status | jq .validator_account_id | tr -d '"'`
    BLOCKHEIGHT=$(http post $mainUrl jsonrpc=2.0 id=dontcare method=query params:='{"request_type": "view_account", "finality": "final", "account_id": "zetsi.shardnet.near"}'| jq -r .result.block_height)
    ISSYNCING=`curl -s http://127.0.0.1:3030/status  | jq .sync_info  | jq .syncing`
    epoch_start_height=$(curl -sSf -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"validators","id":"test","params":[null]}' http://127.0.0.1:3030/ | jq -r .result.epoch_start_height)

    if [ -z "$ISSYNCING" ]; then
        echo "syncing have not data"
        messageSyncing="⚠️ Syncing: Unknown"
        new_status_syncing=true
    else 
        if $ISSYNCING; then
            echo "syncing now"
            messageSyncing="⚠️  Status: Syncing"
            new_status_syncing=true
        else 
            echo "syncing finished"
            messageSyncing="✅ Status: Synchronized"
            new_status_syncing=false
        fi 
    fi

    if [ -z "$BLOCKHEIGHT" ]; then
        echo "block height empty"
        new_block_height="Unknown"
        new_status_block_height=true
    else 
        if [ "$BLOCKHEIGHT" =  "" ]; then
            echo "block height empty"
            new_block_height="Unknown"
            new_status_block_height=true
        else 
            echo "block height present"
            new_block_height=$BLOCKHEIGHT
            if [ "$old_block_height" = "Unknown" ]; then
                old_block_height=0
            fi
            if (($new_block_height>$old_block_height)) ; then
                new_status_block_height=false
                messageBlockHeight="✅ Block Height: ${BLOCKHEIGHT}"
            else
                new_status_block_height=true
                messageBlockHeight="⚠️  Block Height: ${BLOCKHEIGHT}"
            fi
        fi 
    fi

    if [ -z "$VALIDATOR" ]; then
        echo "validator empty"
        new_status_validator=true
    else 
        echo "validator present"
        new_status_validator=false
        messageValidator="✅ Validator: ${VALIDATOR}"

        VALINFO=`curl -s -d '{"jsonrpc": "2.0", "method": "validators", "id": "dontcare", "params": [null]}' -H 'Content-Type: application/json' "$mainUrl" | jq -r --arg VALIDATOR "$VALIDATOR" '.result.current_validators[] | select(.account_id | contains ($VALIDATOR))'`
        if $activeMode; then
            if [ "$step_additional" -ge "$step_before_additional_check" ]; then
                chunks_raw=$(curl -d '{"jsonrpc": "2.0", "method": "validators", "id": "dontcare", "params": [null]}' -H 'Content-Type: application/json' "$additionalUrl" | jq -r '.result.current_validators[] | "\((100 * .num_produced_chunks) / .num_expected_chunks) \(.account_id)"' | grep "$VALIDATOR")
                if [ -z "$chunks_raw" ]; then
                   chunks_now=-100
                   messageChunk="Chunks: $chunks_now%, was now"
                   step_additional=0
                   chunks_prev=$chunks_now
                else
                   echo "chunks_raw: $chunks_raw"
                   chunks_now=${chunks_raw%% *}
                   echo "chunk_now: $chunks_now"
                   messageChunk="Chunks: $chunks_now%, was now"
                   step_additional=0
                   chunks_prev=$chunks_now
                fi
            else
                messageChunk="Chunks: $chunks_prev%, was $step_additional step ago"
            fi
            if [ $(echo "$chunks_now > $missChunk" | bc) -eq 1 ]; then
                new_status_chunk=false
                messageAdditional="✅ ${messageChunk}"
            else
                new_status_chunk=true
                messageAdditional="⚠️  ${messageChunk}"
            fi

            echo "chunk: ${messageAdditional}"
        fi
        echo "VALIDATOR: ${VALIDATOR}"
        echo "FULL VALINFO: $VALINFO"

        expected_blocks=$(echo "$VALINFO" | jq .num_expected_blocks)
        echo "expect: $expected_blocks"

        produced_blocks=$(echo "$VALINFO" | jq .num_produced_blocks)
        echo "produced: $produced_blocks"

        if [[ "$expected_blocks" = "" || "$produced_blocks" = "" ]]; then
            echo "Have not data produced_blocks"
            new_status_have_not_data=true
            new_status_block_not_produced=true
        else
            new_status_have_not_data=false
            messageDataPresent="✅ Data Validator: OK"

            block_diff=$(($expected_blocks-$produced_blocks))

            if [ "$block_diff" =  "" ]; then
                block_diff=0
            fi

            if (($block_diff>=$misslimit)) ; then
                messageBlockProduced="⚠️ Blocks expected/produced: ${expected_blocks}/${produced_blocks}"
                new_status_block_not_produced=true
            else
                messageBlockProduced="✅ Blocks expected/produced: ${expected_blocks}/${produced_blocks}"
                new_status_block_not_produced=false
            fi
        fi
    fi 

    if $notDebug; then 

      need_send_message=false
      if $activeMode; then
        if [ -z "$epoch_start_height" ]; then
            messageEpoch="⚠️ Epoch: Unknown"
        else
            messageEpoch="✅ Epoch: ${epoch_start_height}"
        fi

        if [[ "$new_status_block_height" != "$old_status_block_height" ]]; then 
            need_send_message=true
        fi

        if [[ "$new_status_syncing" != "$old_status_syncing" ]]; then 
            need_send_message=true
        fi

        if [[ "$new_status_validator" != "$old_status_validator" ]]; then 
            need_send_message=true
        fi 

        if [[ "$new_status_have_not_data" != "$old_status_have_not_data" ]]; then 
            need_send_message=true
        fi 

        if [[ "$new_status_block_not_produced" != "$old_status_block_not_produced" ]]; then 
            need_send_message=true
        fi 

        if [[ "$new_status_chunk" != "$old_status_chunk" ]]; then 
            need_send_message=true
        fi 

        # epoch diff and ping
        if $need_send_message_at_next_step; then
            need_send_message=true
            need_send_message_at_next_step=false
        fi
        if (($epoch_start_height != $prev_epoch)); then
            if [ -z "$VALIDATOR" ]; then
                messageEpoch="⚠️ Epoch was/now: ${prev_epoch}/${epoch_start_height}."
            else
                mkdir -p /home/near/near-logs
                near call $VALIDATOR ping '{}' --accountId $ACCOUNT_ID >> /home/near/near-logs/epoch_ping.log
                messageEpoch="⚠️ Epoch was/now: ${prev_epoch}/${epoch_start_height}. Ping executed"
            fi
            need_send_message=true
            need_send_message_at_next_step=true
        fi

	    # temporary - send message if have problem
        if $new_status_block_height; then 
            need_send_message=true
        fi

        if $new_status_validator; then 
            need_send_message=true
        fi 

        if $new_status_have_not_data; then 
            need_send_message=true
        fi 

        if $new_status_block_not_produced; then
            need_send_message=true
        fi 

        if $new_status_syncing; then 
            need_send_message=true
        fi

        if $new_status_chunk; then 
            need_send_message=true
        fi

      else
        if [[ "$new_status_block_height" != "$old_status_block_height" ]]; then 
            need_send_message=true
        fi

        if [[ "$new_status_validator" != "$old_status_validator" ]]; then 
            need_send_message=true
        fi

        if [[ "$new_status_syncing" != "$old_status_syncing" ]]; then 
            need_send_message=true
        fi

        # temporary - send message if have problem
        if $new_status_block_height; then 
            need_send_message=true
        fi

        if $new_status_validator; then 
            need_send_message=true
        fi 

        if $new_status_syncing; then 
            need_send_message=true
        fi
      fi

        if $need_send_message; then 
            Title="Near: on server ${ip_server}"
            if $activeMode; then
                Message="${messageValidator}%0A${messageBlockHeight}%0A${messageSyncing}%0A${messageEpoch}%0A${messageDataPresent}%0A${messageBlockProduced}%0A${messageAdditional}"
            else 
                Message="${messageValidator}%0A${messageBlockHeight}%0A${messageSyncing}"
            fi 

            countSend=0
            while true; do
                MESSAGEINFO=`curl -s \
                    --data parse_mode=HTML \
                    --data chat_id=${telegram_chat_id} \
                    --data text="<b>${Title}</b>%0A${Message}" \
                    --request POST https://api.telegram.org/bot${telegram_bot_token}/sendMessage`
                echo $MESSAGEINFO

                result=$(echo "$MESSAGEINFO" | jq .ok)
                if $result; then
                    echo "Message sended!"
                    break
                fi
                if (( countSend > messageResendCount )); then
                    echo "Message not sended ${messageResendCount} times"
                    break
                fi
                echo "Messege not sended, try again"
                sleep 10s
                ((countSend=countSend+1))
            done

        fi
    fi

    old_status_validator=$new_status_validator
    old_block_height=$new_block_height
    old_status_block_height=$new_status_block_height
    old_status_block_not_produced=$new_status_block_not_produced
    old_status_have_not_data=$new_status_have_not_data
    old_status_syncing=$new_status_syncing
    old_status_chunk=$new_status_chunk
    prev_epoch=$epoch_start_height
    ((step_additional=$step_additional+1))

    echo "sleep $sleep1"
    sleep $sleep1
done