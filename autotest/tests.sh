#!/bin/sh

D=../autotest/test-files
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)
# echo $(pwd)

echo ""
echo "===== COMP9315 22T1 Assignment 2 Testing ====="
echo ""
echo "Data files are in $D"
echo ""

if [ ! -f ass2.zip ]
then
	echo "You must have an ass2.zip file in the current directory"
fi

echo "Setting up \"testing\" directory in current directory"

if [ ! -d testing ]
then
	mkdir testing
else
	files=`ls testing`
	if [ ! -z "$files" ]
	then
		echo "Your testing directory has files in it"
		echo -n "Is it ok to remove them? [y/n] "
		read x
		case "$x" in
		[yY]*) rm -f testing/* ;;
		*) echo "OK ... I can\'t do any more" ; exit 0 ;;
		esac
	fi
fi

cd testing
unzip ../ass2.zip
tar xf $D/supplied.tar

echo ""
echo "Check whether you have modified the ADTs"
echo "The \"make\" will fail if you have"
echo ""

make > .errs 2>&1

nerrs=`grep -c "error:" .errs`
if [ "$nerrs" -gt 0 ]
then
	echo "===== Make Errors ====="
	cat .errs
	echo "===== End Errors ====="
	echo "Your code won't compile using our '*.h' files"
	echo "We assume that this is because you changed the ADT interfaces"
fi

rm -f *

echo ""
echo "Compiling using your submitted files"
echo ""
unzip ../ass2.zip

make > .errs 2>&1

nerrs=`grep -c "error:" .errs`
if [ "$nerrs" -gt 0 ]
then
	echo "===== Make Errors ====="
	cat .errs
	echo "===== End Errors ====="
	echo "Your code doesn't compile!"
fi

# make sure all the binaries got built

nerrs=0
for x in create dump insert select stats
do
	if [ ! -x "$x" ]
	then
		echo "$x did not compile"
		nerrs=`expr "$nerrs" + 1`
	fi
done
if [ "$nerrs" -gt 0 ]
then
	echo "Some executables are missing; limited testing only"
fi 

# make a MALH file

if [ ! -x "create" ]
then
	echo "Can't create a MALH file"
	exit 0
fi

echo ""
echo ""
echo "Test 1: Create an MALH file 3 attrs, 2 pages"
echo ""
./create xyz 3 2 ""
echo ""
echo "Stats on new file"
echo ""
./stats xyz

# insert some tuples

echo ""
echo ""
echo "npages and sp may vary depending on split frequency"
echo "The numbers given are approximate/typical"
echo "ntuples should exactly match the #tuples inserted"
echo ""

if [ ! -x "insert" ]
then
	echo "No 'insert' command to add tuples"
	exit 0
fi

echo ""
echo ""
echo "Test 2: Insert 10 tuples (no splits)"
./insert xyz < $D/data0.txt > /dev/null
echo ""
echo "Stats after inserting 10 tuples"
echo "Should be ntuples=10, npages=2, sp=0"
echo ""
./stats xyz
echo ""
ls -l xyz.*

echo ""
echo ""
echo "Test 3: Insert 30 more tuples (likely 1 split)"
./insert xyz < $D/data1.txt > /dev/null
echo ""
echo "Stats after inserting 30 tuples"
echo "Should be ntuples=40, npages=(2 or 3), sp=(0 or 1)"
echo ""
./stats xyz
echo ""
ls -l xyz.*

echo ""
echo ""
echo "Test 4: Insert 260 more tuples"
./insert xyz < $D/data2.txt > /dev/null
echo ""
echo "Stats after inserting 260 more tuples"
echo "Should be ntuples=300, npages=(10 or 11), sp=(2 or 3)"
echo ""
./stats xyz
echo ""
ls -l xyz.*

echo ""
echo ""
echo "Test 5: Insert 700 more tuples"
./insert xyz < $D/data3.txt > /dev/null
echo ""
echo "Stats after inserting 700 more tuples"
echo "Should be ntuples=1000, npages= ~30, sp= ~15"
echo "Only showing first 10 pages and last 5 pages"
echo ""
./stats xyz | head -16
echo "....."
./stats xyz | tail -5
echo ""
ls -l xyz.*

# Ask some queries

if [ ! -x select ]
then
	echo "Can't run queries"
	exit 0
fi

for i in 6 7 8 9 10 11 12 13 14
do
	q=`cat $D/q$i`
	echo ""
	echo "Test $i: $q"
	./select xyz "$q" | grep '^[0-9]' | sort -n > q$i.out 2>&1
	diffs=`diff q$i.out $D/q$i.exp`
	if [ "$diffs" = "" ]
	then
		echo "Test $i PASSED"
	else
		echo "Test $i FAILED"
	fi
	echo ""
	echo "Your output:"
	cat q$i.out
	echo "---end-of-output---"
	echo "Expected output:"
	cat $D/q$i.exp
	echo "---end-of-output---"
	echo ""
done

# Make new MALH with 100 indentical tuples

rm xyz.*

echo ""
echo ""
echo "Test 15: Create a new MALH file 3 attrs, 4 pages"
echo ""
./create xyz 3 4 ""
echo ""
echo "Stats on new file"
echo ""
./stats xyz

echo ""
echo ""
echo "Test 16: Insert 100 identical tuples"
./insert xyz < $D/data4.txt > /dev/null
echo ""
echo "Stats after inserting tuples"
echo "Should be ntuples=100, npages=(5 or 6), sp=(2 or 3)"
echo "All tuples should in the same bucket"
echo ""
./stats xyz
echo ""
ls -l xyz.*

# large MALH

rm xyz.*

echo ""
echo ""
echo "Test 17: Create a new MALH file 5 attrs, 16 pages"
echo ""
./create xyz 5 16 "" | grep -v '^cv'
echo ""
echo "Stats on new file"
echo ""
./stats xyz

echo ""
echo ""
echo "Test 18: Insert 10000 tuples"
./insert xyz < $D/data5.txt > /dev/null
echo ""
echo "Stats after inserting tuples"
echo "Should be ntuples=10000, npages= ~500, sp=?"
echo "Only showing first 10 pages and last 5 pages"
echo ""
./stats xyz | head -16
echo "....."
./stats xyz | tail -5
echo ""
ls -l xyz.*

# Ask some queries on new MALH

for i in 19 20 21 22 23
do
	q=`cat $D/q$i`
	echo ""
	echo "Test $i: $q"
	./select xyz "$q" | grep '^[0-9]' | sort -n > q$i.out 2>&1
	diffs=`diff q$i.out $D/q$i.exp`
	if [ "$diffs" = "" ]
	then
		echo "Test $i PASSED"
	else
		echo "Test $i FAILED"
	fi
	echo ""
	echo "Your output:"
	cat q$i.out
	echo "---end-of-output---"
	echo "Expected output:"
	cat $D/q$i.exp
	echo "---end-of-output---"
	echo ""
done

