// SPDX-License-Identifier: Apache-2.0

// Command netstack-peer is a test peer for the Java netstack in Klethron's :klethron-tailnet: the Linux
// kernel stack behind a TUN device, bridged to the Java stack as raw IP packets in UDP datagrams, serving a
// transfer check on TCP port 7. Run it only inside a disposable container with CAP_NET_ADMIN, /dev/net/tun,
// IPv6 enabled and net.ipv6.conf.default.accept_dad=0, since nothing answers duplicate address detection on a
// TUN device. Klethron's OracleInteropTest is the client.
//
// Transfer protocol: the client sends "KNS1", the upload and download sizes as big-endian uint64 and a uint32
// seed, then uploads that many bytes of stream(seed) and closes its output. The server sends download bytes of
// stream(seed+1), then one status byte (0 when the upload matched and ended with EOF), and closes.
package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"strconv"
	"sync"
	"unsafe"

	"golang.org/x/sys/unix"
)

const (
	mtu        = 1280 // Tailscale's default TUN MTU, as the Java stack's
	serverPort = 7
	serverV4   = "100.64.0.2"
	serverV6   = "fd7a:115c:a1e0::2"
)

// stream is the shared deterministic payload: xorshift32 bytes, as Harness.bytes in Klethron's Java tests.
type stream struct{ x uint32 }

func newStream(seed uint32) *stream { return &stream{x: seed*0x9e3779b9 + 1} }

func (s *stream) Read(p []byte) (int, error) {
	for i := range p {
		s.x ^= s.x << 13
		s.x ^= s.x >> 17
		s.x ^= s.x << 5
		p[i] = byte(s.x)
	}
	return len(p), nil
}

// udpPeer forwards packets to whichever address last sent one.
type udpPeer struct {
	conn *net.UDPConn
	mu   sync.Mutex
	addr *net.UDPAddr
}

func (u *udpPeer) send(packet []byte) {
	u.mu.Lock()
	addr := u.addr
	u.mu.Unlock()
	if addr != nil {
		if _, err := u.conn.WriteToUDP(packet, addr); err != nil {
			log.Printf("udp write: %v", err)
		}
	}
}

func (u *udpPeer) receive(handle func([]byte)) {
	buf := make([]byte, 65536)
	for {
		n, addr, err := u.conn.ReadFromUDP(buf)
		if err != nil {
			log.Fatalf("udp read: %v", err)
		}
		u.mu.Lock()
		u.addr = addr
		u.mu.Unlock()
		handle(buf[:n])
	}
}

func check(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

// openTun creates the TUN device kns0 with the server addresses and routes to the Java stack's tailnet ranges.
func openTun() *os.File {
	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR, 0)
	check(err)
	var ifr [unix.IFNAMSIZ + 64]byte
	copy(ifr[:], "kns0")
	*(*uint16)(unsafe.Pointer(&ifr[unix.IFNAMSIZ])) = unix.IFF_TUN | unix.IFF_NO_PI
	if _, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(fd), uintptr(unix.TUNSETIFF), uintptr(unsafe.Pointer(&ifr[0]))); errno != 0 {
		log.Fatalf("TUNSETIFF: %v", errno)
	}
	for _, args := range [][]string{
		{"link", "set", "kns0", "mtu", strconv.Itoa(mtu), "up"},
		{"addr", "add", serverV4 + "/32", "dev", "kns0"},
		{"route", "add", "100.64.0.0/10", "dev", "kns0"},
		{"-6", "addr", "add", serverV6 + "/128", "dev", "kns0"},
		{"-6", "route", "add", "fd7a:115c:a1e0::/48", "dev", "kns0"},
	} {
		if out, err := exec.Command("ip", args...).CombinedOutput(); err != nil {
			log.Fatalf("ip %v: %v %s", args, err, out)
		}
	}
	return os.NewFile(uintptr(fd), "tun")
}

func serve(listener net.Listener) {
	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("accept: %v", err)
			return
		}
		go handle(conn)
	}
}

func handle(conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReaderSize(conn, 64<<10)
	var hdr [24]byte
	if _, err := io.ReadFull(reader, hdr[:]); err != nil || string(hdr[:4]) != "KNS1" {
		log.Printf("bad header: %v", err)
		return
	}
	upload := binary.BigEndian.Uint64(hdr[4:])
	download := binary.BigEndian.Uint64(hdr[12:])
	seed := binary.BigEndian.Uint32(hdr[20:])
	written := make(chan error, 1)
	go func() {
		_, err := io.CopyN(conn, newStream(seed+1), int64(download))
		written <- err
	}()
	status := byte(0)
	expected := newStream(seed)
	want := make([]byte, 64<<10)
	got := make([]byte, 64<<10)
	for remaining := upload; remaining > 0; {
		n := min(uint64(len(got)), remaining)
		if _, err := io.ReadFull(reader, got[:n]); err != nil {
			log.Printf("upload read: %v", err)
			status = 1
			break
		}
		_, _ = expected.Read(want[:n])
		if !bytes.Equal(want[:n], got[:n]) {
			status = 2
		}
		remaining -= n
	}
	if status == 0 {
		if _, err := reader.ReadByte(); !errors.Is(err, io.EOF) {
			status = 3
		}
	}
	if err := <-written; err != nil {
		log.Printf("download write: %v", err)
		return
	}
	if _, err := conn.Write([]byte{status}); err != nil {
		log.Printf("status write: %v", err)
		return
	}
	_ = conn.(*net.TCPConn).CloseWrite()
	// Linger until the client closes too, so both FINs are exchanged.
	_, _ = io.Copy(io.Discard, reader)
	log.Printf("transfer up=%d down=%d status=%d", upload, download, status)
}

func main() {
	listen := flag.String("listen", "127.0.0.1:0", "UDP address for packets to and from the Java stack")
	flag.Parse()
	udpAddr, err := net.ResolveUDPAddr("udp", *listen)
	check(err)
	conn, err := net.ListenUDP("udp", udpAddr)
	check(err)
	peer := &udpPeer{conn: conn}
	tun := openTun()
	go func() {
		buf := make([]byte, 65536)
		for {
			n, err := tun.Read(buf)
			if err != nil {
				log.Fatalf("tun read: %v", err)
			}
			peer.send(buf[:n])
		}
	}()
	go peer.receive(func(packet []byte) {
		if _, err := tun.Write(packet); err != nil {
			log.Printf("tun write: %v", err)
		}
	})
	for _, addr := range []string{serverV4, serverV6} {
		l, err := net.Listen("tcp", net.JoinHostPort(addr, strconv.Itoa(serverPort)))
		check(err)
		go serve(l)
	}
	fmt.Printf("LISTEN %s\n", conn.LocalAddr())
	_ = os.Stdout.Sync() // Fails harmlessly on pipes.
	select {}
}
