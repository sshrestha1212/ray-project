# Use the official Ray image as the base
FROM rayproject/ray:2.41.0

WORKDIR /app

# Copy your application code
COPY summarize.py /app
COPY requirements.txt /app

RUN pip install torch transformers fastapi
RUN pip install -r requirements.txt

