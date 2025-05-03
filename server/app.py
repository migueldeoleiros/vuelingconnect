from fastapi import FastAPI
import random
import time
from enum import Enum

app = FastAPI()

class MsgType(Enum):
    flightStatus = 0
    alert = 1

class FlightStatus(Enum):
    scheduled = 0
    departed = 1
    arrived = 2
    delayed = 3
    cancelled = 4

class AlertType(Enum):
    medical = 0
    evacuation = 1
    aliens = 2
    fire = 3

class BleMessage:
    def __init__(self, msg_type, flight_number=None, status=None, alert_type=None, timestamp=None):
        self.msg_type = msg_type
        self.flight_number = flight_number
        self.status = status
        self.alert_type = alert_type
        self.timestamp = timestamp or int(time.time())

    @classmethod
    def flight_status(cls, flight_number, status, timestamp=None):
        return cls(MsgType.flightStatus, flight_number=flight_number, status=status, timestamp=timestamp)

    @classmethod
    def alert(cls, alert_type, timestamp=None):
        return cls(MsgType.alert, alert_type=alert_type, timestamp=timestamp)

flight_numbers = [f"VY{i:04d}" for i in range(2375, 2389)]

def generate_random_flight_info():
    status = random.choice(list(FlightStatus))
    return BleMessage.flight_status(
        flight_number=random.choice(flight_numbers),
        status=status
    )

def generate_random_alert():
    alert_type = random.choice(list(AlertType))
    return BleMessage.alert(alert_type=alert_type)

@app.get("/flight-status")
async def get_flight_status():
    messages = []
    for _ in range(1):
        msg_type = random.choice(list(MsgType))
        if msg_type == MsgType.flightStatus:
            messages.append(generate_random_flight_info())
        else:
            messages.append(generate_random_alert())
    
    return [
        {
            "msg_type": msg.msg_type.name,
            "flight_number": msg.flight_number,
            "status": msg.status.name if msg.status else None,
            "alert_type": msg.alert_type.name if msg.alert_type else None,
            "timestamp": msg.timestamp
        } for msg in messages
    ]

# quitar alertas, 