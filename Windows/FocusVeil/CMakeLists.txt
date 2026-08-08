cmake_minimum_required(VERSION 3.20)

project(FocusVeilWindows LANGUAGES CXX)

add_executable(FocusVeil WIN32
    src/main.cpp
)

target_compile_features(FocusVeil PRIVATE cxx_std_17)

if(MSVC)
    target_compile_options(FocusVeil PRIVATE /W4 /utf-8 /permissive-)
else()
    target_compile_options(FocusVeil PRIVATE -Wall -Wextra -Wpedantic)
endif()

target_link_libraries(FocusVeil PRIVATE
    advapi32
    comctl32
    dwmapi
    gdi32
    shell32
    user32
    winhttp
)
