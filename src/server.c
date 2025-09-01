#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <unistd.h>
#include <ctype.h>
#include <sys/time.h>

#define MAX_REQUESTS 100
#define INITIAL_CAPACITY 100
#define BUFFER_SIZE 1024
#define IP_RANGE_SIZE 64  
#define PORT_RANGE_SIZE 16 

pthread_mutex_t lock;
void process_request(const char *request, char *response);
void handle_network_mode(int port);
void *handle_client(void *socket_desc);

typedef struct {
    char ip_range[IP_RANGE_SIZE];
    char port_range[PORT_RANGE_SIZE];
    struct {
        char ip[INET_ADDRSTRLEN];
        int port;
    } *queries;
    int query_count;
    int query_capacity;
} FirewallRule;

FirewallRule *rules;
int rule_count = 0;
int rule_capacity = INITIAL_CAPACITY;

char **requests;
int request_count = 0;
int request_capacity = INITIAL_CAPACITY;

void ensure_rule_capacity();
void ensure_request_capacity();
void trim_whitespace(char *str);

int main(int argc, char *argv[]) {
    pthread_mutex_init(&lock, NULL);
    
    rule_capacity = INITIAL_CAPACITY;
    rules = malloc(rule_capacity * sizeof(FirewallRule));
    request_capacity = INITIAL_CAPACITY;
    requests = malloc(request_capacity * sizeof(char*));
    
    if (argc == 2 && strcmp(argv[1], "-i") == 0) {
        char request[BUFFER_SIZE];
        char response[BUFFER_SIZE];
        
        while (fgets(request, sizeof(request), stdin) != NULL) {
            request[strcspn(request, "\n")] = 0;
            pthread_mutex_lock(&lock);
            process_request(request, response);
            pthread_mutex_unlock(&lock);
            printf("%s\n", response);
        }
    } else if (argc == 2) {
        int port = atoi(argv[1]);
        if (port > 0 && port <= 65535) {
            handle_network_mode(port);
        } else {
            fprintf(stderr, "Invalid port number.\n");
            return 1;
        }
    } else {
        fprintf(stderr, "Usage: %s -i | %s <port>\n", argv[0], argv[0]);
        return 1;
    }
    pthread_mutex_destroy(&lock);
    for (int i = 0; i < rule_count; i++) {
        free(rules[i].queries);
    }
    free(rules);
    for (int i = 0; i < request_count; i++) {
        free(requests[i]);
    }
    free(requests);
    return 0;
}
void ensure_rule_capacity() {
    if (rule_count >= rule_capacity) {
        rule_capacity *= 2;
        rules = realloc(rules, rule_capacity * sizeof(FirewallRule));
        if (rules == NULL) {
            perror("Failed to allocate memory for rules");
            exit(1);
        }
    }
}
void ensure_request_capacity() {
    if (request_count >= request_capacity) {
        request_capacity *= 2;
        requests = realloc(requests, request_capacity * sizeof(char*));
        if (requests == NULL) {
            perror("Failed to allocate memory for requests");
            exit(1);
        }
    }
}
void trim_whitespace(char *str) {
    char *start = str;
    char *end;
    
    // Find start of non-whitespace
    while (isspace((unsigned char)*start)) start++;
    
    // If string is all whitespace
    if (*start == '\0') {
        *str = '\0';
        return;
    }
    
    // Find end of non-whitespace
    end = start + strlen(start) - 1;
    while (end > start && isspace((unsigned char)*end)) end--;
    
    // Copy trimmed string back to original location
    size_t len = end - start + 1;
    memmove(str, start, len);
    str[len] = '\0';
}
bool is_valid_ip(const char *ip) {
    struct sockaddr_in sa;
    return inet_pton(AF_INET, ip, &(sa.sin_addr)) != 0;
}
bool is_valid_ip_range(const char *ip_range) {
    char ip_start[IP_RANGE_SIZE], ip_end[IP_RANGE_SIZE];
    if (strchr(ip_range, '-') == NULL) {
        return is_valid_ip(ip_range);
    }
    sscanf(ip_range, "%63[^-]-%63s", ip_start, ip_end);
    return is_valid_ip(ip_start) && is_valid_ip(ip_end);
}
bool is_valid_port_range(const char *port_range) {
    int start, end;
    if (strchr(port_range, '-') == NULL) {
        int port = atoi(port_range);
        return port >= 0 && port <= 65535;
    }
    sscanf(port_range, "%d-%d", &start, &end);
    return start >= 0 && end <= 65535 && start < end;
}
bool ip_to_integer(const char *ip, unsigned int *result) {
    struct in_addr addr;
    if (inet_pton(AF_INET, ip, &addr) == 1) {
        *result = ntohl(addr.s_addr);
        return true;
    }
    return false;
}
bool is_within_ip_range(const char *ip, const char *range) {
    unsigned int ip_int, start_int, end_int;
    if (!ip_to_integer(ip, &ip_int)) {
        return false;
    }
    char ip_start[IP_RANGE_SIZE], ip_end[IP_RANGE_SIZE];
    if (strchr(range, '-') == NULL) {
        if (!ip_to_integer(range, &start_int)) {
            return false;
        }
        return ip_int == start_int;
    } else {
        sscanf(range, "%63[^-]-%63s", ip_start, ip_end);
        if (!ip_to_integer(ip_start, &start_int) || !ip_to_integer(ip_end, 
&end_int)) {
            return false;
        }
        return (ip_int >= start_int && ip_int <= end_int);
    }
}
bool is_within_port_range(int port, const char *range) {
    int start, end;
    if (strchr(range, '-') == NULL) {
        return port == atoi(range);
    }
    sscanf(range, "%d-%d", &start, &end);
    return port >= start && port <= end;
}
void add_rule(const char *ip_range, const char *port_range, char *response) {
    ensure_rule_capacity();
    if (!is_valid_ip_range(ip_range) || !is_valid_port_range(port_range)) {
        strncpy(response, "Invalid rule", BUFFER_SIZE - 1);
        response[BUFFER_SIZE - 1] = '\0';
        return;
    }
    for (int i = 0; i < rule_count; i++) {
        if (strcmp(rules[i].ip_range, ip_range) == 0 && strcmp(rules[i].port_range,
port_range) == 0) {
            strncpy(response, "Rule already exists", BUFFER_SIZE - 1);
            response[BUFFER_SIZE - 1] = '\0';
            return;
        }
    }
    FirewallRule *rule = &rules[rule_count++];
    strncpy(rule->ip_range, ip_range, IP_RANGE_SIZE - 1);
    strncpy(rule->port_range, port_range, PORT_RANGE_SIZE - 1);
    rule->ip_range[IP_RANGE_SIZE - 1] = '\0';
    rule->port_range[PORT_RANGE_SIZE - 1] = '\0';
    rule->query_count = 0;
    rule->query_capacity = INITIAL_CAPACITY;
    rule->queries = malloc(rule->query_capacity * sizeof(*rule->queries));
    strncpy(response, "Rule added", BUFFER_SIZE - 1);
    response[BUFFER_SIZE - 1] = '\0';
}
void check_connection(const char *ip, int port, char *response) {
    if (!is_valid_ip(ip) || port < 0 || port > 65535) {
        strncpy(response, "Illegal IP address or port specified", BUFFER_SIZE - 1);
        response[BUFFER_SIZE - 1] = '\0';
        return;
    }
    for (int i = 0; i < rule_count; i++) {
        bool ip_match = is_within_ip_range(ip, rules[i].ip_range);
        bool port_match = is_within_port_range(port, rules[i].port_range);
        if (ip_match && port_match) {
            FirewallRule *rule = &rules[i];
            if (rule->query_count >= rule->query_capacity) {
                rule->query_capacity *= 2;
                rule->queries = realloc(rule->queries, rule->query_capacity * 
sizeof(*rule->queries));
            }
            strncpy(rule->queries[rule->query_count].ip, ip, INET_ADDRSTRLEN - 1);
            rule->queries[rule->query_count].ip[INET_ADDRSTRLEN - 1] = '\0';
            rule->queries[rule->query_count++].port = port;
            strncpy(response, "Connection accepted", BUFFER_SIZE - 1);
            response[BUFFER_SIZE - 1] = '\0';
            return;
        }
    }
    strncpy(response, "Connection rejected", BUFFER_SIZE - 1);
    response[BUFFER_SIZE - 1] = '\0';
}
void delete_rule(const char *ip_range, const char *port_range, char *response) {
    // First check if the rule format is valid
    if (!is_valid_ip_range(ip_range) || !is_valid_port_range(port_range)) {
        strncpy(response, "Rule invalid", BUFFER_SIZE - 1);
        response[BUFFER_SIZE - 1] = '\0';
        return;
    }
    
    // Rule is valid, now check if it exists
    for (int i = 0; i < rule_count; i++) {
        if (strcmp(rules[i].ip_range, ip_range) == 0 && strcmp(rules[i].port_range,
port_range) == 0) {
            free(rules[i].queries);
            for (int j = i; j < rule_count - 1; j++) {
                rules[j] = rules[j + 1];
            }
            rule_count--;
            strncpy(response, "Rule deleted", BUFFER_SIZE - 1);
            response[BUFFER_SIZE - 1] = '\0';
            return;
        }
    }
    strncpy(response, "Rule not found", BUFFER_SIZE - 1);
    response[BUFFER_SIZE - 1] = '\0';
}
void list_rules(char *response) {
    char temp[BUFFER_SIZE];
    response[0] = '\0';
    for (int i = 0; i < rule_count; i++) {
        snprintf(temp, BUFFER_SIZE - 1, "Rule: %s %s\n", rules[i].ip_range, 
rules[i].port_range);
        strncat(response, temp, BUFFER_SIZE - strlen(response) - 1);
        for (int j = 0; j < rules[i].query_count; j++) {
            snprintf(temp, BUFFER_SIZE - 1, "Query: %s %d\n", 
rules[i].queries[j].ip, rules[i].queries[j].port);
            strncat(response, temp, BUFFER_SIZE - strlen(response) - 1);
        }
    }
    if (rule_count == 0) {
        strncat(response, "No rules found\n", BUFFER_SIZE - strlen(response) - 1);
    }
}
void list_requests(char *response) {
    response[0] = '\0';
    char temp[BUFFER_SIZE];
    for (int i = 0; i < request_count && i < MAX_REQUESTS; i++) {
        snprintf(temp, BUFFER_SIZE - 1, "%s\n", requests[i]);
        strncat(response, temp, BUFFER_SIZE - strlen(response) - 1);
    }
    if (request_count == 0) {
        strncat(response, "No requests found\n", BUFFER_SIZE - strlen(response) - 
1);
    }
}
void handle_network_mode(int port) {
    int server_fd;
    struct sockaddr_in address;
    int addrlen = sizeof(address);
    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("Socket creation failed");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 128) < 0) {
        perror("Listen failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }
    printf("Server started\n");
    int new_socket;
    while ((new_socket = accept(server_fd, (struct sockaddr *)&address, 
(socklen_t*)&addrlen)) >= 0) {
        printf("Accepted connection: socket %d\n", new_socket);
        pthread_t client_thread;
        int *socket_ptr = malloc(sizeof(int));
        *socket_ptr = new_socket;
        if (pthread_create(&client_thread, NULL, handle_client, (void*)socket_ptr) 
< 0) {
            perror("Thread creation failed");
            free(socket_ptr);
            close(new_socket);
        } else {
            pthread_detach(client_thread);
            printf("Thread created for socket %d\n", new_socket);
        }
    }
    close(server_fd);
}
void process_request(const char *request, char *response) {
    response[0] = '\0';
    char trimmed_request[BUFFER_SIZE] = {0};
    strncpy(trimmed_request, request, BUFFER_SIZE - 1);
    trim_whitespace(trimmed_request);
    if (request_count < MAX_REQUESTS && strcmp(trimmed_request, "R") != 0) {
        ensure_request_capacity();
        requests[request_count] = malloc(BUFFER_SIZE);
        strncpy(requests[request_count], trimmed_request, BUFFER_SIZE - 1);
        request_count++;
    }
    if (strncmp(trimmed_request, "A ", 2) == 0) {
        char ip_range[IP_RANGE_SIZE] = {0};
        char port_range[PORT_RANGE_SIZE] = {0};
        if (sscanf(trimmed_request + 2, "%63s %15s", ip_range, port_range) == 2) {
            add_rule(ip_range, port_range, response);
        } else {
            strncpy(response, "Invalid rule format", BUFFER_SIZE - 1);
        }
    } else if (strncmp(trimmed_request, "C ", 2) == 0) {
        char ip[INET_ADDRSTRLEN] = {0};
        int port;
        if (sscanf(trimmed_request + 2, "%15s %d", ip, &port) == 2) {
            check_connection(ip, port, response);
        } else {
            strncpy(response, "Illegal IP address or port specified", BUFFER_SIZE -
1);
        }
    } else if (strncmp(trimmed_request, "D ", 2) == 0) {
        char ip_range[IP_RANGE_SIZE] = {0};
        char port_range[PORT_RANGE_SIZE] = {0};
        if (sscanf(trimmed_request + 2, "%63s %15s", ip_range, port_range) == 2) {
            delete_rule(ip_range, port_range, response);
        } else {
            strncpy(response, "Invalid rule format", BUFFER_SIZE - 1);
        }
    } else if (strcmp(trimmed_request, "R") == 0) {
        list_requests(response);
    } else if (strcmp(trimmed_request, "L") == 0) {
        list_rules(response);
    } else {
        strncpy(response, "Illegal request", BUFFER_SIZE - 1);
    }
    response[BUFFER_SIZE - 1] = '\0';
}
void *handle_client(void *socket_desc) {
    struct timeval timeout;
    timeout.tv_sec = 10;
    timeout.tv_usec = 0;
    int sock = *(int*)socket_desc;
    free(socket_desc);
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    char buffer[BUFFER_SIZE];
    char response[BUFFER_SIZE];
    // Process exactly one request (matching client behavior)
    int recv_len = recv(sock, buffer, BUFFER_SIZE - 1, 0);
    if (recv_len > 0) {
        buffer[recv_len] = '\0';  // Properly null-terminate
        buffer[strcspn(buffer, "\n")] = '\0';  // Remove newlines
        pthread_mutex_lock(&lock);
        process_request(buffer, response);
        pthread_mutex_unlock(&lock);
        send(sock, response, strlen(response), 0);
        printf("Thread for socket %d completed request\n", sock);
    }
    close(sock);
    printf("Thread for socket %d closed socket and exiting\n", sock);
    return NULL;
}