message format
    msg_type:   "FlightStatus": 0
                "info": 1
                "alert": 2
    if msg_type == FlightStatus
        flight number: VY2383
        status:     "Scheduled": 0,
                    "Departed": 1,
                    "Arrived": 2,
                    "Delayed": 3,
                    "Cancelled": 4
    else if msg_type == info || msg_type == alert
        message: string
    timestamp: epoch format
    


## Relay Order Priority
Timestamp (Newest First):
Newer messages are prioritized over older ones
This ensures the most recent information propagates first
Hop Count (Lowest First):
When timestamps are identical, messages with lower hop counts are prioritized
This gives preference to messages that haven't traveled as far in the network
Rotation:
After selecting a message to relay, the index is incremented
This creates a round-robin effect where all eligible messages get relayed