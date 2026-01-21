#!/usr/bin/env bash
set -euo pipefail

# Переменная для типа сборки
BUILD_TYPE="$1"

# Переменные используемые для контроля версий и ревизий
VERSION="1.0.3"
REV_FILE="/build/src/.revision"

#Счётчик количества запусков конвейера
RUN_COUNTER="/build/src/.run_number"

if [ -f "$RUN_COUNTER" ]; then
    RUN_NUMBER=$(cat "$RUN_COUNTER")
else
    RUN_NUMBER=0
fi

RUN_NUMBER=$((RUN_NUMBER + 1))
echo "$RUN_NUMBER" > "$RUN_COUNTER"

# Реализация счётчика ревизия для разных версий
declare -A REVS

if [ -f "$REV_FILE" ]; then
    while read -r type ver rev; do
        REVS["$type,$ver"]=$rev
    done < "$REV_FILE"
fi

OLD_REV=${REVS["$BUILD_TYPE,$VERSION"]:-0}
REV=$((OLD_REV + 1))

REVS["$BUILD_TYPE,$VERSION"]=$REV

> "$REV_FILE"
for key in "${!REVS[@]}"; do
    IFS=',' read type ver <<< "$key"
    echo "$type $ver ${REVS[$key]}" >> "$REV_FILE"
done

echo "Starting build: nginx-$BUILD_TYPE-$VERSION-$REV"

# Интеграция с ccache, локально с хостом с которого запускается скрипт
export CC="ccache gcc"
export CXX="ccache g++"

# Ветвление на типы сборок
CFLAGS=""
LDFLAGS=""

case "$BUILD_TYPE" in
    release)
        CFLAGS="-O2"
        ;;
    debug)
        CFLAGS="-O0 -g"
        ;;
    coverage)
        CFLAGS="--coverage -O0"
        LDFLAGS="--coverage"
        ;;
    *)
        echo "unknown build type: $BUILD_TYPE"
        exit 1
        ;;
esac

export CFLAGS
export LDFLAGS

# Функция вызова сборки
cd /build/src/nginx

build_nginx() {
    ./auto/configure "$@"
    make
}

# Сборка coverage
if [ "$BUILD_TYPE" = "coverage" ]; then
    COVERAGE_DIR="/build/artifacts/coverage"
    mkdir -p "$COVERAGE_DIR"

    ./auto/configure \
        --with-cc-opt="-O0 -g --coverage" \
        --with-ld-opt="--coverage -lgcov"
    make
    echo "Testing coverage..."

    # Coverage тестирования nginx -v
    /build/src/nginx/objs/nginx -v

    echo "Capturing coverage data..."

    # Подсчёт покрытия с помощью lcov
    lcov --capture --directory . --output-file "$COVERAGE_DIR"/coverage.info

    # Подсчёт процента покрытия по lines
    NEW_COVERAGE=$(lcov --summary "$COVERAGE_DIR"/coverage.info | grep lines | awk '{print $2}' | tr -d '%') 

    COVERAGE_FILE="/build/reports/coverage_report.txt"
    PREV_COVERAGE=0
    if [ -f "$COVERAGE_FILE" ]; then
        PREV_COVERAGE=$(cat "$COVERAGE_FILE")
    fi

    rm -rf $COVERAGE_DIR

    echo "Previous coverage: $PREV_COVERAGE%"
    echo "New coverage: $NEW_COVERAGE%"

    # Сравнение покрытия со значением из coverage_report
    if (( $(echo "$NEW_COVERAGE < $PREV_COVERAGE" | bc -l) )); then
        echo "Error: coverage decreased!"
        exit 1
    fi

    # Запись нового значения покрытия в coverage report
    echo "$NEW_COVERAGE" > "$COVERAGE_FILE"
    echo "Coverage report saved in $COVERAGE_DIR"

else

# Вызов сборки для не coverage версии
    build_nginx
fi

# Создание временной директории для DEB-пакета
DEB_DIR="/build/artifacts/nginx-${BUILD_TYPE}-${VERSION}-${REV}"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/local/bin"

# Копирование собранного бинарника в директорию для deb-пакета
BIN_PATH="objs/nginx"
OUTPUT="/build/artifacts/nginx-$BUILD_TYPE-${VERSION}-${REV}_tmp"
cp "$BIN_PATH" "$DEB_DIR/usr/local/bin/nginx"

# strip релиз сборок
if [ "$BUILD_TYPE" = "release" ]; then
    strip "$DEB_DIR/usr/local/bin/nginx"
fi

# Control-файл
cat > "$DEB_DIR/DEBIAN/control" <<EOF
Package: nginx
Version: ${VERSION}-${BUILD_TYPE}-${REV}
Section: web
Priority: optional
Architecture: amd64
Maintainer: Ivan Bystrov <ibystrov1@mail.ru>
Description: nginx built in a pipeline for InfoTecs internship
Depends: libc6, libpcre3, zlib1g, libssl-dev
EOF

# Сборка deb-пакета
dpkg-deb --build "$DEB_DIR"

# Удаление временных файлов и директорий, в том числе в src
rm -rf $DEB_DIR
echo "rm -rf ${DEB_DIR}"

rm -f /build/artifacts/nginx-$BUILD_TYPE-$VERSION-${REV}_tmp
echo "rm -f /build/artifacts/nginx-${BUILD_TYPE}"

make clean

echo "Deb package created at ${DEB_DIR}.deb"

# Запуск скрипта создающего отчёт
/build/scripts/report_writer.sh \
    "$RUN_NUMBER" \
    "${VERSION}-${BUILD_TYPE}-${REV}" \
    "$BUILD_TYPE" \
    "${COVERAGE_VALUE:-N/A}"
