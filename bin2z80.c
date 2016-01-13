#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc,char **argv) {

  int f_in;
  int f_out;
  int address;
  int run;

  if (argc != 5) {
    printf("Usage: bin2z80 bin_file output_file dump_address run_address\n");
    return -1;
  }

  address = atoi(argv[3]);
  if (address == 0) {
    printf("Invalid address.\n");
    return -1;
  }

  run = atoi(argv[4]);
  if (run == 0) {
    printf("Invalid run address.\n");
    return -1;
  }

  f_in = open(argv[1],O_RDONLY);
  if (-1 == f_in) {
    printf("Can't open file %s. Aborting.\n",argv[1]);
    return -1;
  }

  f_out = open(argv[2],O_WRONLY|O_CREAT|O_TRUNC,S_IRUSR|S_IWUSR);
  if (-1 == f_out) {
    printf("Can't open file %s. Aborting.\n",argv[2]);
    return -1;
  }

  unsigned char buffer[49152];
  memset(buffer,0,49152);
  unsigned char b2[3];

  buffer[10]=0x3F; // interrupt register
  buffer[12]=0x0E; // white border
  buffer[29]=0x01; // IM 1
  buffer[30]=23;
  buffer[31]=0;
  buffer[32]=run%256;
  buffer[33]=run/256;
  buffer[34]=3; // 128K
  buffer[35]=0x10; // page 0; BASIC ROM
  buffer[37]=4; // AY enabled
  write(f_out,buffer,55);
  memset(buffer,0,49152);
  memset(buffer+6144,56,768);
  read(f_in,buffer+address-16384,49152);
  b2[0] = 0xFF;
  b2[1] = 0xFF;
  b2[2] = 8;
  write(f_out,b2,3);
  write(f_out,buffer,16384);
  b2[0] = 0xFF;
  b2[1] = 0xFF;
  b2[2] = 5;
  write(f_out,b2,3);
  write(f_out,buffer+16384,16384);
  b2[0] = 0xFF;
  b2[1] = 0xFF;
  b2[2] = 3;
  write(f_out,b2,3);
  write(f_out,buffer+32768,16384);
  close(f_in);
  close(f_out);
  return 0;
}
