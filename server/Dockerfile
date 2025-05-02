FROM python:3.9-alpine

WORKDIR /server

COPY ./requirements.txt /server/requirements.txt

RUN pip install --no-cache-dir --upgrade -r /server/requirements.txt

COPY ./app.py /server/app.py

CMD ["fastapi", "run", "app.py", "--port", "80"]