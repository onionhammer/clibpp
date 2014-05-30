
all: clibpp

clibpp: clibpp.nim test.o
	nimrod cpp --parallelBuild:1 clibpp

test.o: test.cpp test.hpp
	clang++ -c -std=c++11 test.cpp

clean:
	rm -rf nimcache
	rm test.o clibpp