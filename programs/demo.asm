; Ode to Joy (Beethoven, public domain) -- Ballistic Synth demo
; v0-2 pad | v3 bass | v4 lead | v5 lead, octave below | v6 kick | v7 hi-hat

tempo 132

wave v0-2 triangle 60
env  v0-2 200 1000 10 750
wave v3   saw 100
env  v3 5 300 9 100
wave v4   square 48
env  v4 5 200 11 100
wave v5   sine 60
env  v5 10 300 10 200
wave v6   sine 230
env  v6 0 300 0 0
wave v7   noise 50
env  v7 0 50 0 0

; bar 1
chord c4 maj
on v3 c2
on v4 e5
on v5 e4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 e5
on v5 e4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v3 g2
on v4 f5
on v5 f4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 g5
on v5 g4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 2
chord g3 maj
on v3 g2
on v4 g5
on v5 g4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 f5
on v5 f4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v3 d3
on v4 e5
on v5 e4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 d5
on v5 d4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 3
chord c4 maj
on v3 c2
on v4 c5
on v5 c4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 c5
on v5 c4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v3 g2
on v4 d5
on v5 d4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 e5
on v5 e4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 4
chord g3 maj
on v3 g2
on v4 e5
on v5 e4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 d5
on v5 d4
on v7 c4
wait 1/2b
on v3 d3
on v4 d5
on v5 d4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 5
chord c4 maj
on v3 c2
on v4 e5
on v5 e4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 e5
on v5 e4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v3 g2
on v4 f5
on v5 f4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 g5
on v5 g4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 6
chord g3 maj
on v3 g2
on v4 g5
on v5 g4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 f5
on v5 f4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v3 d3
on v4 e5
on v5 e4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 d5
on v5 d4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 7
chord c4 maj
on v3 c2
on v4 c5
on v5 c4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 c5
on v5 c4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v3 g2
on v4 d5
on v5 d4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 e5
on v5 e4
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; bar 8
chord g3 maj
on v3 g2
on v4 d5
on v5 d4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v4 c5
on v5 c4
on v7 c4
wait 1/2b
chord c4 maj
on v3 c2
on v4 c5
on v5 c4
on v6 a1
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b
on v7 c4
wait 1/2b

; ending
chord c4 maj
on v3 c2
on v4 c5
on v5 c4
on v6 a1
on v7 c4
wait 2b
off all
wait 1500
halt
