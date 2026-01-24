FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code (your app.py is inside App/)
COPY App/ /app/

EXPOSE 8080

CMD ["python", "app.py"]
