# RTMP Recorder Project Documentation

This project is a complete RTMP streaming recording solution that captures live video streams, converts them to time-based MP4 chunks, and automatically uploads them to AWS S3. It consists of three main services orchestrated with Docker Compose.

## Project Overview

The system works as a pipeline:

1. **RTMP Server** (nginx-rtmp) receives live streams and records them as time-based FLV chunks (default: 15 minutes)
2. **Remuxer** (FFmpeg) converts each FLV chunk to MP4 format individually
3. **Publisher** (AWS CLI) uploads MP4 chunks to S3 storage as they become available

## File-by-File Breakdown

### `docker-compose.yml`

**Purpose**: Orchestrates the entire multi-container application

**Services Defined**:

#### `rtmp` Service

- **Image**: `tiangolo/nginx-rtmp:latest` - NGINX with RTMP module
- **Container Name**: `rtmp`
- **Ports**:
  - `1935:1935` - RTMP streaming port
  - `80:80` - HTTP health check and file browsing
- **Environment Variables**:
  - `CHUNK_DURATION_MINUTES` - Duration of each recording chunk (default: 15 minutes)
- **Volumes**:
  - `./nginx/nginx.conf:/etc/nginx/nginx.conf:ro` - Custom NGINX configuration
  - `recordings_data:/recordings` - Shared volume for recorded files
- **Health Check**: Curls localhost to verify service is running

#### `remuxer` Service

- **Image**: `jrottenberg/ffmpeg:4.4-alpine` - FFmpeg for video processing
- **Container Name**: `remuxer`
- **Environment Variables**:
  - `QUIET_SECONDS` - Wait time before processing files (default: 60s)
  - `FLV_MAX_AGE_SECONDS` - Age threshold for FLV cleanup (default: 0 = disabled)
- **Volumes**:
  - `recordings_data:/recordings` - Access to recorded files
  - `./remuxer/remux.sh:/remux.sh:ro` - Processing script
- **Entry Point**: Runs the remux script

#### `publisher` Service

- **Image**: `amazon/aws-cli:latest` - AWS CLI for S3 uploads
- **Container Name**: `publisher`
- **Environment Variables**:
  - `AWS_REGION`, `S3_BUCKET`, `S3_PREFIX` - AWS configuration
  - `PUBLIC_ACL` - Whether to make S3 objects public
  - `SYNC_INTERVAL_SECONDS` - Upload frequency (default: 10s)
  - `RECORDINGS_DIR` - Source directory for uploads
- **Volumes**:
  - `recordings_data:/recordings:ro` - Read-only access to recordings
  - `./publisher/publish.sh:/publish.sh:ro` - Upload script
- **Entry Point**: Runs the publish script

#### Shared Volume

- `recordings_data` - Persistent volume shared between all containers

### `Makerfile`

**Purpose**: Provides convenient Docker Compose shortcuts

**Commands Available**:

- `make up` - Start all services in detached mode
- `make down` - Stop and remove all containers
- `make logs` - Follow logs from all services (last 200 lines)
- `make ps` - Show running container status
- `make restart` - Restart all services
- `make clean` - Stop containers and remove volumes (destructive)

**Usage**: Run `make <command>` from the project root directory.

### `nginx/nginx.conf`

**Purpose**: Configures NGINX with RTMP module for stream recording

**Key Sections**:

#### Global Settings

- `user root` - Run as root user
- `worker_processes auto` - Auto-detect CPU cores
- `worker_connections 1024` - Max connections per worker

#### RTMP Block

- **Listen Port**: `1935` (standard RTMP port)
- **Chunk Size**: `4096` bytes
- **Application**: `live` - RTMP endpoint path
- **Recording Configuration**:
  - Records all streams (`record all`)
  - Saves to `/recordings/flv` directory
  - Uses `.flv` suffix (RTMP-native format)
  - `record_unique on` - Prevents overwriting
  - `record_append off` - Creates separate files for each chunk
  - `record_interval` - Creates new file every N minutes (configurable)
  - `record_max_size 1000M` - Safety limit to prevent oversized files

#### HTTP Block

- **Port**: `80` for health checks and file browsing
- **Health Endpoint**: `/` returns "nginx-rtmp alive"
- **File Browser**: `/recordings/` serves recorded files with directory listing
- **MIME Types**: Properly serves MP4 and FLV files
- **Cache Control**: Disables caching for recordings

**Stream URL Format**: `rtmp://<server-ip>/live/<stream-key>`

### `publisher/publish.sh`

**Purpose**: Continuously syncs MP4 recordings to AWS S3

**Configuration Variables**:

- `RECORDINGS_DIR` - Source directory (default: `/recordings/mp4`)
- `SYNC_INTERVAL_SECONDS` - Upload frequency (default: 30s)
- `S3_BUCKET` - Target S3 bucket (required)
- `S3_PREFIX` - S3 key prefix (required)
- `AWS_REGION` - AWS region (default: `us-west-2`)

**Process Flow**:

1. Validates required environment variables
2. Enters infinite loop
3. Runs `aws s3 sync` with these options:
   - `--size-only` - Only sync if file sizes differ
   - `--no-progress` - Suppress progress output
   - `--only-show-errors` - Minimal logging
4. Waits for specified interval before next sync

**Sync Behavior**: One-way sync (local → S3), only adds/updates files, never deletes.

### `README.md`

**Purpose**: Complete deployment guide for AWS EC2

**Content Sections**:

#### AWS Setup (One-time)

- S3 bucket creation and configuration
- IAM role creation with required permissions:
  - `s3:PutObject`, `s3:PutObjectAcl`
  - `s3:ListBucket`, `s3:DeleteObject`
  - `s3:GetBucketLocation`
- Security group configuration (ports 22, 1935, 80)

#### EC2 Instance Setup

- Recommended instance: Amazon Linux 2023, t3.small
- Docker and Docker Compose v2 installation
- User permissions configuration

#### Project Configuration

- Environment variables setup (`.env` file)
- Required settings: AWS region, S3 bucket, sync intervals

#### Testing and Verification

- FFmpeg test stream command
- Verification steps for recordings
- S3 access methods (direct, CloudFront)

#### Troubleshooting Guide

- Common issues and solutions
- Log checking commands
- Performance tuning tips

#### Optional Features

- User-data script for automated deployment
- Lifecycle management recommendations

### `remuxer/remux.sh`

**Purpose**: Converts FLV recordings to MP4 format and manages file cleanup

**Configuration Variables**:

- `FLV_DIR` - Source directory (`/recordings/flv`)
- `MP4_DIR` - Output directory (`/recordings/mp4`)
- `QUIET_SECONDS` - Wait time before processing (default: 60s)
- `FLV_MAX_AGE_SECONDS` - Age threshold for FLV cleanup (default: 0 = disabled)

**Key Functions**:

#### `is_quiet_enough()`

- Checks if a file hasn't been modified for `QUIET_SECONDS`
- Uses `stat` command to get file modification time
- Ensures streams are finished before processing

#### `remux_one()`

- Converts single FLV file to MP4
- Creates lock file to prevent concurrent processing
- Uses FFmpeg with `-c copy` (stream copy, no re-encoding)
- Handles errors gracefully, removes failed outputs
- Cleans up lock files

#### `cleanup_old_flv()`

- Removes old FLV files if `FLV_MAX_AGE_SECONDS` > 0
- Only deletes FLV if corresponding MP4 exists
- Uses `find` with `-mmin` for age-based filtering

**Main Loop**:

1. Scans FLV directory for `.flv` files
2. Processes chunk files that are "quiet enough" (finished recording)
3. Converts each chunk individually to MP4
4. Runs cleanup for old FLV files
5. Sleeps 5 seconds before next iteration

**Chunked Processing**: Each time-based chunk is processed independently, allowing for continuous streaming with regular MP4 output.

**File Safety**: Uses lock files and modification time checks to avoid processing active recordings.

## System Architecture

```
RTMP Stream → NGINX-RTMP → FLV Files → FFmpeg → MP4 Files → AWS S3
                ↓
           Health Check (HTTP:80)
```

## Data Flow

1. **Ingestion**: RTMP streams arrive at port 1935
2. **Chunked Recording**: NGINX saves streams as time-based FLV chunks in `/recordings/flv` (default: 15-minute segments)
3. **Processing**: Remuxer waits for each chunk to finish, then converts FLV chunk to MP4
4. **Storage**: MP4 chunks are saved to `/recordings/mp4` with timestamps
5. **Publishing**: Publisher syncs new MP4 chunks to S3 every few seconds
6. **Cleanup**: Old FLV files are optionally removed after successful MP4 conversion

**Chunking Benefits**:

- Continuous streaming produces manageable file sizes
- Failed chunks don't affect entire stream
- Faster upload times for individual segments
- Better for playback and seeking

## Key Features

- **Chunked Live Recording**: Captures RTMP streams in configurable time segments (default: 15 minutes)
- **Format Conversion**: Converts RTMP-native FLV chunks to web-friendly MP4
- **Continuous Processing**: Each chunk is processed independently for uninterrupted streaming
- **Cloud Storage**: Automatic S3 upload with configurable intervals
- **Health Monitoring**: HTTP endpoints for service status
- **File Management**: Automatic cleanup of intermediate files
- **Fault Tolerance**: Lock files prevent corruption, error handling throughout
- **Scalability**: Container-based architecture for easy deployment
- **Manageable File Sizes**: Time-based chunking prevents oversized files

## Environment Variables Summary

| Variable                 | Service   | Default    | Description                         |
| ------------------------ | --------- | ---------- | ----------------------------------- |
| `CHUNK_DURATION_MINUTES` | rtmp      | 15         | Recording chunk duration in minutes |
| `QUIET_SECONDS`          | remuxer   | 60         | Wait time before processing         |
| `FLV_MAX_AGE_SECONDS`    | remuxer   | 0          | FLV cleanup threshold               |
| `AWS_REGION`             | publisher | us-west-2  | AWS region                          |
| `S3_BUCKET`              | publisher | (required) | Target S3 bucket                    |
| `S3_PREFIX`              | publisher | (required) | S3 key prefix                       |
| `PUBLIC_ACL`             | publisher | -          | Make objects public                 |
| `SYNC_INTERVAL_SECONDS`  | publisher | 10         | Upload frequency                    |

This system provides a complete, production-ready solution for RTMP stream recording and cloud storage.
