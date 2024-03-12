clear
rm -f *.o
rm -rf testing
make
zip ass2.zip Makefile *.c *.h
sh  autotest/tests.sh