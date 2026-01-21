import os
import sys
import subprocess

project_dir = os.getcwd()
docker_context = os.path.join(project_dir, "docker")
home_dir = os.path.expanduser("~")
ccache_host_path = os.path.join(home_dir, ".ccache")
image = "build:latest"

# Функция проверки на наличие образа
def image_exists(image: str) -> bool:
    result = subprocess.run(
        ["docker", "image", "inspect", image],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    return result.returncode == 0

# Функция сборки образа из Dockerfile
def build_image():
    print(f"Building image {image}")
    subprocess.run(
        ["docker", "build", "-t", image, docker_context],
        check=True
    )

# Функция запуска контейнера с использованием ccache
def run_container(cmd: str):
    subprocess.run(
        [
            "docker", "run",
            "--rm",
            "-v", f"{project_dir}:/build",
            "-v", f"{ccache_host_path}:/root/.ccache",
            "-w", "/build",
            image,
            f"/build/scripts/build.sh", cmd
        ]
    )

# Запуск скрипта с парсингом аргументов
def main ():
    if len(sys.argv) < 2:
        print("Usage: python run_build.py [release|debug|coverage]")
        sys.exit(1)

    build_type = sys.argv[1]
    
    if not image_exists(image):
        build_image()
    else:
        print(f"Using existing image {image}")

    run_container(build_type)

if __name__ == "__main__":
    main()
