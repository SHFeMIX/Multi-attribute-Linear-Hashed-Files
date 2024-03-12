make
rm  -f  R.*
./create R 3 2 "0,0:1,0:2,0:0,1:1,1:2,1"
clear
./insert R < data1.txt