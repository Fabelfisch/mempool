cd software/apps
make clean
config=minpool make matrix_mul
cd ../../hardware
make clean
config=minpool make compile
config=minpool app=matrix_mul make sim
make trace