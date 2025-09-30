# Gamemaker Project Cleaner
When you use Gamemaker - especially older versions - uneccessary files may start to accumulate in your project folders.

While not obstructive it clutters your working directory.

This tools scans your project and tries to delete as many of these files as possible.

<img width="1234" height="747" alt="image" src="https://github.com/user-attachments/assets/517ca208-dc78-482b-b536-2472161241ae" />

<img width="1002" height="465" alt="image" src="https://github.com/user-attachments/assets/47b40b78-3fdd-4410-9f29-a7fe9af4b68d" />


## WARNING
THIS TOOL WILL DELETE FILES FROM YOUR PROJECT.

DO A BACKUP OF YOUR PROJECT BEFORE USING

The tool will prompt you to confirm before deleting

## --- gamemaker-project-cleaner ---
Usage: gamemaker-project-cleaner < project path >

Example: gamemaker-project-cleaner C:/repos/gamemaker-project/

## Improvement
Does the tool delete too little?

Does the tool delet too much?

Send me a dm on discord or create an issue here.

## Build instructions
1) Install zig
2) `zig build -Doptimize=ReleaseFast` in project root
Program will appear zig-out/bin/

## Dependencies
This tool uses ZPL for parsing JSON5.

https://github.com/zpl-c/zpl
