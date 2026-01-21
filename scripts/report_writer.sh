#!/usr/bin/env bash
set -euo pipefail

cd /build
RUN_NUMBER="$1"
REVISION="$2"
BUILD_TYPE="$3"
COVERAGE="${4:-N/A}"

REPORTS_DIR=/build/reports/build
REPORT_TIME=$(date +"%Y%m%d_%H%M%S")
REPORT_NAME="${REPORTS_DIR}/build_report_${REPORT_TIME}.txt"

cat > "$REPORT_NAME" <<EOF
Build number: $RUN_NUMBER
Revision number: $REVISION
Build type: $BUILD_TYPE
Coverage: $COVERAGE
EOF
echo "Build report is saved in: ${REPORT_NAME}"