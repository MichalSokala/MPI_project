% =====================================================================
% DANE DOT. INFRASTRUKTURY CMUROWEJ
% =====================================================================
int: C_;                      % liczba klastrów obliczeniowych
set of int: C = 1..C_;        % zbiór klastrów obliczeniowych

enum T = {CPU, RAM};          % rodzaje zasobów obliczeniowych
array [C,T] of int: CRes;     % zasoby klastrów

array[C} of int: IdlePower;

% =====================================================================
% DANE DOT. OFEROWANYCH USŁUG
% =====================================================================
enum S;                         % Oferowane usługi np. S = {WEB, DB, VIDEO};

array[S, T] of int: Req;        % Wymagane zasoby obliczeniowe przez pojedynczy pod

array[S] of int: MinReplicas;   % Minimalna liczba replik kazdej uslugi

% =====================================================================
% Koszt jednostkowy zasobów i wagi funkcji celu
% =====================================================================
float: UnitTransCost;                 % Koszt za przesłanie 1 jedn. ruchu na  1 km
array [T] of float: UnitCompCost;     % Koszt jednostkowy zasobów: [CPU, RAM]
y
float: WeightComp;
float: WeightTrans;

% =====================================================================
% ZMIENNE DECYZYJNE
% =====================================================================
int: MaxReplicas = max([MinReplicas[s] | s in S]);

array[S, C] of var 0..MaxReplicas: x;     % Liczba podow uslugi S na wezle C
array[C] of var 0..1: is_active;     % Status wezla; 1 = wlaczony, 0 = wylaczony

% =====================================================================
% WARUNKI BRZEGOWE (CONSTRAINTS)
% =====================================================================

% 1. DOSTĘPNOŚĆ ZASOBÓW W KLASTRACH
% Zużycie zasobów (CPU/RAM) przez instancje uruchomione w danym klastrze nie może przekroczyć jego pojemności.
constraint forall(c in C, t in T) (
    sum(s in S) (x[s, c] * Req[s, t]) <= CRes[c, t] * active[c]
);

% 2. OGRANICZONA ILOSC PODOW DANEJ USLUGI
constraint forall(s in S) (
    sum(c in C) (x[s, c]) >= MinReplicas[s]
);

% 3. WYLACZENIE PUSTYCH WEZLOW
constraint forall(c in C) (
    sum(s in S)(x[s, c]) >= active[c]
);

% ==========================================PRZYKLAD Z WYKLADU=============================================
% 2. ROZPłYW RUCHU (BILANS RUCHU)
% Cały ruch napływający do klastra c1 dla usługi s musi zostać w pełni obsłużony (przekierowany do klastrów c2).
% constraint forall(c1 in C, s in S) (
%    sum(c2 in C) (y[c1, s, c2]) >= Demand[c1, s]
% );

% 3. OGRANICZENIA WYDAJNOŚCIOWE INSTANCJI
% Ruch przekierowany do klastra c2 dla usługi s nie może przekroczyć łącznej wydajności uruchomionych tam instancji.
% constraint forall(c2 in C, s in S) (
%    sum(c1 in C) (y[c1, s, c2]) <= x[s, c2] * ServiceRate[s]
% );

% 4. OGRANICZENIE OPÓŹNIENIA E2E
% Ruch może być przesłany z c1 do c2 tylko wtedy, gdy opóźnienie między ich lokalizacjami mieści się w limicie usługi.
%constraint forall(c1 in C, s in S, c2 in C) (
%    y[c1, s, c2] > 0 -> D[CL[c1], CL[c2]] <= MaxDelay[s]
%);

%constraint forall(c1 in C, s in S, c2 in C where D[CL[c1], CL[c2]] > MaxDelay[s]) (
%    y[c1, s, c2] = 0
%);
% ============================================================================================================================
% =====================================================================
% FUNKCJA KOSZTU (CELU)
% =====================================================================

% Koszt obliczeniowy: suma kosztów zasobów (CPU, RAM) zużytych przez instancje we wszystkich klastrach
var float: comp_cost = sum(c in C, s in S, t in T)(
    int2float(x[s, c] * Req[s, t]) * UnitCompCost[t]
);

% Koszt transmisji: suma iloczynów przesłanego ruchu i odległości (opóźnienia) między klastrami
var float: trans_cost = sum(c1 in C, s in S, c2 in C)(
    int2float(y[c1, s, c2] * D[CL[c1], CL[c2]])
) * UnitTransCost;

% Całkowity koszt ważony
var float: total_cost = WeightComp * comp_cost + WeightTrans * trans_cost;

solve minimize total_cost;

% =====================================================================
% RAPORT WYNIKOW
% =====================================================================
output [
    "--- ALOKACJA INSTANCJI (x) ---\n"] ++
    [ "Klaster \(c) (\(CL[c])): " ++ concat([ "\(s):\(x[s,c]) " | s in S]) ++ "\n" | c in C ] ++
    ["\n--- ROZPRZYW RUCHU (y) ---\n"] ++
    [ "Klaster \(c1) -> Klaster \(c2) | Usługa \(s) | Ruch: \(y[c1,s,c2]) (Opóźnienie: \(D[CL[c1], CL[c2]]))\n"
      | c1, c2 in C, s in S where fix(y[c1,s,c2]) > 0 ] ++
    ["\n--- KOSZTY ---\n",
     "Koszt obliczeń: ", show(comp_cost), "\n",
     "Koszt transmisji: ", show(trans_cost), "\n",
     "Koszt całkowity (ważony): ", show(total_cost), "\n"
];