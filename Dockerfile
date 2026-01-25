FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the App folder
COPY App/ ./App/

# Move into the correct folder where app.py exists
WORKDIR /app/App

EXPOSE 8080

CMD ["python", "app.py"]
