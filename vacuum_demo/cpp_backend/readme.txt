cd ~/mnt/development/engr/Programming/SERA_VACU/VACUUM_FLUT/vacuum_demo/cpp_backend

rm -rf build        # 🔥 예전 캐시 싹 지우기
mkdir build
cd build

cmake ..            # 여기서 이제 /home/nsyun/Qt/... 를 보게 될 거예요
cmake --build . --config Release

