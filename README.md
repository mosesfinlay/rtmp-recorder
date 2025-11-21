# RTMP Recorder

Records RTMP streams to S3 automatically.

## Quick Start (Local)

```bash
cp .env.example .env
# Edit .env with your AWS credentials and S3 bucket
docker compose build
docker compose up -d
```

Stream to: `rtmp://localhost/live/your-stream-key`

## EC2 Deployment

### 1. Prep AWS (one-time)

**Create S3 bucket** for recordings

**Create IAM role** for EC2 with S3 write access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:PutObjectAcl", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::YOUR_BUCKET", "arn:aws:s3:::YOUR_BUCKET/*"]
    }
  ]
}
```

**Security Group:**

- TCP 22 (SSH)
- TCP 1935 (RTMP)
- TCP 80 (optional health check)

### 2. Launch EC2

- **AMI:** Amazon Linux 2023
- **Size:** t3.small
- **Disk:** 20 GB
- **Attach IAM role** from step 1

### 3. Install Docker

```bash
sudo dnf -y update
sudo dnf -y install docker git
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# Install Docker Compose
sudo mkdir -p /usr/libexec/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 \
  -o /usr/libexec/docker/cli-plugins/docker-compose
sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose

# Re-login to apply docker group
exit
```

### 4. Deploy

```bash
git clone <your-repo-url> rtmp-recorder
cd rtmp-recorder
cp .env.example .env
nano .env  # Set AWS_REGION, S3_BUCKET, S3_PREFIX
docker compose build
docker compose up -d
```

### 5. Stream

Stream to: `rtmp://<EC2_IP>/live/<stream-key>`

Recordings auto-upload to S3 at: `s3://YOUR_BUCKET/YOUR_PREFIX/`

## Commands

**Start:** `docker compose up -d`

**Stop:** `docker compose down`

**Logs:** `docker compose logs -f`

**Restart:** `docker compose restart`

**Update code:**

```bash
git pull
docker compose build
docker compose up -d
```

## Environment Variables

```env
AWS_REGION=us-west-2
S3_BUCKET=your-bucket-name
S3_PREFIX=videos
PUBLIC_ACL=false
CHUNK_DURATION_MINUTES=15
SYNC_INTERVAL_SECONDS=10
QUIET_SECONDS=60
FLV_MAX_AGE_SECONDS=0
```

## Troubleshooting

**Check logs:** `docker compose logs -f`

**No S3 uploads:** Verify EC2 IAM role attached

**Can't connect:** Check security group allows TCP 1935

**Check recordings:** `docker exec rtmp ls -la /recordings/`
