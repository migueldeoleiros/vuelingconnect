from fastapi import FastAPI
import random
import uuid
import time
from datetime import datetime

app = FastAPI()

status_message_map = {
    "Scheduled": "Flight scheduled to depart on time.",
    "Departed": "Flight has successfully departed.",
    "Arrived": "Flight has landed successfully.",
    "Delayed": "Flight delayed due to weather conditions.",
    "Cancelled": "Flight cancelled due to technical issues.",
}

flight_numbers = [
    "VY2375",
    "VY2376",
    "VY2377",
    "VY2378",
    "VY2379",
    "VY2380",
    "VY2381",
    "VY2382",
    "VY2383",
    "VY2384",
    "VY2385",
    "VY2386",
    "VY2387",
    "VY2388",
]


def generate_random_flight_info():

    flight_status = random.choice(list(status_message_map.keys()))
    flight_message = status_message_map[flight_status]

    return {
        "original_message_timestamp": datetime.now().isoformat(),
        "source": "vueling-api-server",
        "message_id": str(uuid.uuid4()),
        "flight_number": random.choice(flight_numbers),
        "flight_message": flight_message,
        "flight_status": flight_status,
    }


@app.get("/flight-status")
async def get_flight_status():
    # Generate a list of 5 random flight status objects
    flight_statuses = [generate_random_flight_info() for _ in range(5)]
    return flight_statuses
