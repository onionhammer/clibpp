#include "test.hpp"

using namespace std;

int pp::test::notherName = 120;

void pp::test::output() {
	cout << "hello world!" << endl;
}

int pp::test::multiply(int value, int by) {
	fieldName = 240;
	return value * by;
}