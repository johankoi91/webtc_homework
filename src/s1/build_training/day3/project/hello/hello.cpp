#include "hello.h"
#include "util.h"
#include <iostream>

void say_hello() {
    std::cout << "Hello GN + " << util_name() << std::endl;
}