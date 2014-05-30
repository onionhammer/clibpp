#include "test.hpp"

using namespace std;

int test::notherName = 120;


void test::output() {
	cout << "hello world!" << endl;
}

int test::multiply(int value, int by) {
	fieldName = 240;
	return value * by;
}