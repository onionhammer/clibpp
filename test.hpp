#include <iostream>

namespace pp {
	class test {

	public:
		static void output();

		int multiply(int value, int by);

		template<typename T>
		T max(T a, T b) {
		    return a > b ? a : b;
		};

		int fieldName;

		static int notherName;
	};

	class test_sub: test {
	public:
		int childf();
	};
}