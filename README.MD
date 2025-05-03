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
