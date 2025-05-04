from fastapi import FastAPI
import random
import time
from enum import Enum
from datetime import datetime, timedelta

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
    def __init__(self, msg_type, flight_number=None, status=None, alert_type=None, timestamp=None, eta=None):
        self.msg_type = msg_type
        self.flight_number = flight_number
        self.status = status
        self.alert_type = alert_type
        self.timestamp = timestamp or int(time.time())
        self.eta = eta

    @classmethod
    def flight_status(cls, flight_number, status, timestamp=None, eta=None):
        return cls(MsgType.flightStatus, flight_number=flight_number, status=status, timestamp=timestamp, eta=eta)

    @classmethod
    def alert(cls, alert_type, timestamp=None):
        return cls(MsgType.alert, alert_type=alert_type, timestamp=timestamp)

flight_numbers = [f"VY{i:04d}" for i in range(2375, 2389)]

def generate_random_flight_info():
    status = random.choice(list(FlightStatus))
    current_timestamp = int(time.time())
    
    # Calculate eta based on flight status
    eta = None
    if status == FlightStatus.scheduled or status == FlightStatus.delayed:
        # Random ETA between 1 and 5 hours from now
        future_time = datetime.now() + timedelta(hours=random.randint(1, 5))
        eta = int(future_time.timestamp())
    elif status == FlightStatus.departed:
        # For departed flights, use a time that's already passed (departure time)
        past_time = datetime.now() - timedelta(minutes=random.randint(15, 120))
        eta = int(past_time.timestamp())
    elif status == FlightStatus.arrived:
        # For arrived flights, use a time that's already passed (arrival time)
        past_time = datetime.now() - timedelta(minutes=random.randint(5, 60))
        eta = int(past_time.timestamp())
    # For cancelled flights, eta remains None
    
    return BleMessage.flight_status(
        flight_number=random.choice(flight_numbers),
        status=status,
        timestamp=current_timestamp,
        eta=eta
    )

def generate_random_alert():
    alert_type = random.choice(list(AlertType))
    return BleMessage.alert(alert_type=alert_type)

@app.get("/flight-status")
async def get_flight_status():
    messages = []
    for _ in range(1):
        # Uncomment to generate alerts
        # msg_type = random.choice(list(MsgType))
        # if msg_type == MsgType.flightStatus:
        messages.append(generate_random_flight_info())
        # else:
        #     messages.append(generate_random_alert())
    
    return [
        {
            "msg_type": msg.msg_type.name,
            "flight_number": msg.flight_number,
            "status": msg.status.name if msg.status else None,
            "alert_type": msg.alert_type.name if msg.alert_type else None,
            "eta": msg.eta,
            "timestamp": msg.timestamp
        } for msg in messages
    ]

# quitar alertas, 