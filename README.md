# Flutter Map Agent

<img width="1194" height="813" alt="Screenshot 2026-04-20 at 23 17 42" src="https://github.com/user-attachments/assets/71cc5fbe-3154-4204-8c32-2c8ea790f8fa" />

<img width="1194" height="813" alt="Screenshot 2026-04-20 at 23 51 43" src="https://github.com/user-attachments/assets/7b83a38e-603b-4e27-9c66-339c0bd83e7f" />

<img width="1194" height="813" alt="Screenshot 2026-04-20 at 16 12 04" src="https://github.com/user-attachments/assets/7b7c6d68-7b09-471c-ae7a-5a2998103cd5" />

<img width="1215" height="781" alt="Screenshot 2026-04-14 at 11 45 49" src="https://github.com/user-attachments/assets/24467cea-8174-4245-bbd8-162d9b78ee76" />


This is a Flutter Application that tries to mimic the Claude Desktop with its Map Artifact Window. All geographic
requests to the LLM will be displayed in the Map Area of the application. Since this is a Flutter application, it can
be deloyed as a Web, MacOS/Win Native, or Mobile Device app. 

### Requirements

The follwing API KEYS will be needed: 
* Mapfan API Key to display Maps
* Anthropic API Key to connect to Claude
* OpenAPI API Key to connect to ChatGPT

The URL of a Model Context Protocol(MCP) Service is required.

### To Build

* Create a `lib/config/app_config.dart` based on the app_config.dart.sample and place the required
API KEYS as well as the MCP URL.

* Issue the following command to create and run a MacOS Desktop binary: 

    ```flutter run -d macos ```
