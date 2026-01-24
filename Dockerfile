FROM python:3.11-slim

WORKDIR /app

# install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# copy your flask app folder
App/app.py

EXPOSE 8080

CMD ["python", "app.py"]
