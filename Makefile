CFLAGS = -Wall -Werror -g
SRCDIR = src

all: server client

server: $(SRCDIR)/server.o
	$(CC) $(CFLAGS) -o server $(SRCDIR)/server.o -lpthread

$(SRCDIR)/server.o: $(SRCDIR)/server.c
	$(CC) $(CFLAGS) -c $(SRCDIR)/server.c -o $(SRCDIR)/server.o

client: $(SRCDIR)/client.o
	$(CC) $(CFLAGS) -o client $(SRCDIR)/client.o

$(SRCDIR)/client.o: $(SRCDIR)/client.c
	$(CC) $(CFLAGS) -c $(SRCDIR)/client.c -o $(SRCDIR)/client.o

clean:
	rm -f $(SRCDIR)/*.o server client