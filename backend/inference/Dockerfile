FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip python3.10-venv git build-essential \
    libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/hunyuan3d
RUN git clone --depth 1 https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git . \
    && python3.10 -m pip install --upgrade pip \
    && python3.10 -m pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 \
       --index-url https://download.pytorch.org/whl/cu124 \
    && python3.10 -m pip install -r requirements.txt

WORKDIR /app
COPY requirements.txt .
RUN python3.10 -m pip install -r requirements.txt
COPY . .

ENV HUNYUAN_REPO_PATH=/opt/hunyuan3d
ENV HUNYUAN_MODEL_PATH=tencent/Hunyuan3D-2.1
ENV HUNYUAN_SHAPE_SUBFOLDER=hunyuan3d-dit-v2-1
ENV DABSKY_RESULT_DIR=/tmp/dabsky-results
EXPOSE 8080

CMD ["python3.10", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
