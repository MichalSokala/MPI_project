% =====================================================================
% DANE DOT. INFRASTRUKTURY CMUROWEJ
% =====================================================================
int: N_;                      % liczba węzłów obliczeniowych
set of int: N = 1..N_;        % zbiór węzłów obliczeniowych

enum T = {CPU, RAM};          % rodzaje zasobów obliczeniowych
array [N,T] of int: NRes;     % zasoby węzłów

array[N] of int: IdlePower;   % moc pobierana w trybie IDLE
array[N] of int: MaxPower;   % moc pobierana przy maksymalnym obciążeniu

% =====================================================================
% DANE DOT. OFEROWANYCH USŁUG
% =====================================================================
enum S;                         % Oferowane usługi np. S = {WEB, DB, VIDEO};

array[S, T] of int: Req;        % Wymagane zasoby obliczeniowe przez pojedynczy pod

array[S] of int: MinReplicas;   % Minimalna liczba replik kazdej uslugi

% =====================================================================
% ZMIENNE DECYZYJNE
% =====================================================================
int: MaxReplicas = max([MinReplicas[s] | s in S]);

array[S, N] of var 0..MaxReplicas: x;     % Liczba podow uslugi S na wezle N
array[N] of var 0..1: is_active;     % Status wezla; 1 = wlaczony, 0 = wylaczony

array[N] of var int: used_cpu = [sum(s in S)(x[s, n] * Req[s, CPU]) | n in N];

% =====================================================================
% WARUNKI BRZEGOWE (CONSTRAINTS)
% =====================================================================

% 1. DOSTĘPNOŚĆ ZASOBÓW W KLASTRACH
% Zużycie zasobów (CPU/RAM) przez instancje uruchomione w danym klastrze nie może przekroczyć jego pojemności.
constraint forall(n in N, t in T) (
    sum(s in S) (x[s, n] * Req[s, t]) <= NRes[n, t] * is_active[n]
);

% 2. OGRANICZONA ILOSC PODOW DANEJ USLUGI
constraint forall(s in S) (
    sum(n in N) (x[s, n]) >= MinReplicas[s]
);

% 3. WYLACZENIE PUSTYCH WEZLOW
constraint forall(n in N) (
    sum(s in S)(x[s, n]) >= is_active[n]
);

% =====================================================================
% FUNKCJA KOSZTU (CELU)
% =====================================================================


% Koszt obliczeniowy: suma kosztów zasobów (CPU, RAM) zużytych przez instancje we wszystkich klastrach
var float: total_power = sum(n in N)(
    int2float(IdlePower[n]*is_active[n]) + int2float(MaxPower[n] - IdlePower[n]) * int2float(used_cpu[n])/int2float(NRes[n, CPU])
);

solve minimize total_power;

% =====================================================================
% RAPORT WYNIKOW
% =====================================================================
%output [
%    "--- ALOKACJA INSTANCJI (x) ---\n"] ++
%    [ "Wez \(c) (\(CL[n])): " ++ concat([ "\(s):\(x[s,c]) " | s in S]) ++ "\n" | n in N ] ++
%    ["\n--- ROZPRZYW RUCHU (y) ---\n"] ++
%    [ "Klaster \(c1) -> Klaster \(c2) | Usługa \(s) | Ruch: \(y[n1,s,c2]) (Opóźnienie: \(D[CL[n1], CL[n2]]))\n"
%      | c1, c2 in C, s in S where fix(y[n1,s,c2]) > 0 ] ++
%    ["\n--- KOSZTY ---\n",
%     "Koszt obliczeń: ", show(comp_cost), "\n",
%     "Koszt transmisji: ", show(trans_cost), "\n",
%     "Koszt całkowity (ważony): ", show(total_cost), "\n"
%];