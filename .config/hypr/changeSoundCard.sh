#!/bin/bash

printarr() { declare -n __p="$1"; for k in "${!__p[@]}"; do printf "%s=%s\n" "$k" "${__p[$k]}" ; done ;  }  

SINKS=$(pactl list short sinks)

SINKS_ALLOWED=("JBL" "bluez_output" "pci-0000_00" "AudioQuest" "hdmi-stereo")
declare -A SINKS_MAPPED
declare -A SINKS_INDEXES_MAPPED
CURRENT_SINK_NAME=$(pactl get-default-sink)

while IFS= read -r SINK; do
	for SINK_ALLOWED in "${SINKS_ALLOWED[@]}"; do
		if [[ "$SINK" =~ $SINK_ALLOWED ]]; then
			SINK_NUMBER=$(echo $SINK | grep -oP "^[0-9]{1,5}")
			SINKS_MAPPED[$SINK_NUMBER]=$(echo $SINK | awk '{print $2}' )
			break
		fi	
	done
done <<< "$SINKS"

ITERATOR=1
for SINK_NUMBER in "${!SINKS_MAPPED[@]}"
do
	SINKS_INDEXES_MAPPED[$ITERATOR]=$SINK_NUMBER
	ITERATOR=$((ITERATOR+1))
done

FOUND_SINK=false
ACTIVE_SINK_INDEX=1
SINKS_MAPPED_SIZE=${#SINKS_MAPPED[@]}
for SINK_NUMBER in "${!SINKS_MAPPED[@]}"
do
	if [[ "${SINKS_MAPPED[$SINK_NUMBER]}" == "$CURRENT_SINK_NAME" ]]; then
		break
	fi
	ACTIVE_SINK_INDEX=$((ACTIVE_SINK_INDEX+1))
done

NEXT_SINK_INDEX=$((ACTIVE_SINK_INDEX+1))
NEXT_SINK_NUMBER="${SINKS_INDEXES_MAPPED[$NEXT_SINK_INDEX]}"
if [[ "$NEXT_SINK_INDEX" -gt "$SINKS_MAPPED_SIZE" ]]; then
	NEXT_SINK_NUMBER="${SINKS_INDEXES_MAPPED[1]}"
fi

echo $NEXT_SINK_INDEX
echo $NEXT_SINK_NUMBER
printarr SINKS_MAPPED

pactl set-default-sink $NEXT_SINK_NUMBER
