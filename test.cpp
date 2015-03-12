#include "test.hpp"

using std::cout;
using std::endl;

int pp::test::notherName = 120;

void pp::test::output() {
	cout << "hello world!" << endl;
}

int pp::test::multiply(int value, int by) {
	fieldName = 240;
	return value * by;
}

int pp::test_sub::childf() { return 42; }
