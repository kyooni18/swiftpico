cmake_minimum_required(VERSION 3.13)
add_library(mock_cmake STATIC mock_cmake.c)
target_include_directories(mock_cmake PUBLIC ${CMAKE_CURRENT_LIST_DIR})
