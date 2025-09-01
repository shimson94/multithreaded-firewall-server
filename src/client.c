#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <unistd.h>

#define BUFFER_SIZE 1024

int main(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <serverHost> <serverPort> <command>\n", argv[0]);
        return 1;
    }
    
    int sock;
    struct sockaddr_in serv_addr;
    
    // Dynamically allocate command buffer based on arguments
    size_t command_length = 0;
    for (int i = 3; i < argc; i++) {
        command_length += strlen(argv[i]) + 1;
    }
    
    char *command = malloc(command_length);
    
    if (!command) {
        perror("Failed to allocate memory for command");
        return 1;
    }
    
    command[0] = '\0';
    
    for (int i = 3; i < argc; i++) {
        strcat(command, argv[i]);
        if (i < argc - 1) {
            strcat(command, " ");
        }
    }
    
    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        perror("Socket creation error");
        free(command);
        return -1;
    }
    
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(atoi(argv[2]));
    
    if (strcmp(argv[1], "localhost") == 0) {
        argv[1] = "127.0.0.1";
    }
    
    if (inet_pton(AF_INET, argv[1], &serv_addr.sin_addr) <= 0) {
        perror("Invalid address");
        free(command);
        return -1;
    }
    
    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("Connection Failed");
        free(command);
        return -1;
    }
    
    send(sock, command, strlen(command), 0);
    free(command);  // Free command buffer after sending
    
    // Allocate response buffer dynamically
    char *buffer = malloc(BUFFER_SIZE);
    if (!buffer) {
        perror("Failed to allocate memory for response buffer");
        close(sock);
        return 1;
    }
    
    read(sock, buffer, BUFFER_SIZE);
    printf("%s\n", buffer);
    
    free(buffer);  // Free the response buffer
    close(sock);
    return 0;
}