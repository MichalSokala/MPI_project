int: N_;
set of int: N = 1..N_;
enum T = {CPU, RAM};
array[N, T] of int: NRes;         % zasoby fizyczne wezlow: [vCPU, GiB]
array[N, T] of int: SystemReserve; % rezerwa na kubelet, CNI, DaemonSet itp.
array[N] of int: MustStayOn;      % 1: wezel musi pozostac wlaczony
array[N] of int: IdlePower;       % moc calego wlaczonego wezla bez podow [W]
array[N] of int: MaxPower;        % szacowana moc dla pelnego obciazenia CPU [W]

enum S;
array[S, T] of int: Req;         % requests jednego poda: [vCPU, GiB]
array[S] of int: MinReplicas;

% Zapotrzebowanie na dodatkowe repliki podczas uruchamiania wylaczonej VM.
% ReserveScale = 0: brak dodatkowego zapasu, 1: prognoza bazowa itd.
int: VMStartMinutes;
array[S] of int: ExtraReplicasPerMinute;
int: ReserveScale;
array[S] of int: ShortagePenalty; % kara za brak 1 rezerwy [W-ekwiwalent]
int: ShortagePenaltyMultiplier;   % 100 = bazowa kara, 0 = bez kary
int: SpreadPenalty;              % kara za kazda kolejna replike na wezle [W-ekw.]

array[S] of int: BurstNeed = [
    ReserveScale * VMStartMinutes * ExtraReplicasPerMinute[s] | s in S
];
int: MaxReplicas = max([MinReplicas[s] | s in S]);
int: MaxBurst = max([BurstNeed[s] | s in S]);

% =====================================================================
% ZMIENNE DECYZYJNE
% =====================================================================
array[S, N] of var 0..MaxReplicas: x;          % aktualnie uruchomione pody
array[N] of var 0..1: is_active;              % stan VM / wezla
array[S, N] of var 0..MaxBurst: standby;      % WIRTUALNE dodatkowe repliki
array[S] of var 0..MaxBurst: shortage;        % liczba replik bez gotowego miejsca
array[S, N] of var 0..MaxReplicas: colocated; % nadmiar replik tej samej uslugi

array[N] of var int: used_cpu = [
    sum(s in S)(x[s,n] * Req[s,CPU]) | n in N
];
array[N] of var int: used_ram = [
    sum(s in S)(x[s,n] * Req[s,RAM]) | n in N
];

% =====================================================================
% OGRANICZENIA
% =====================================================================

% 1. Dokladnie wymagane repliki (w tym projekcie ruch bazowy jest staly).
constraint forall(s in S)(
    sum(n in N)(x[s,n]) = MinReplicas[s]
);

% 2. Granica liczby podow danej uslugi na pojedynczym wezle.
% MaxReplicas jest tylko zakresem technicznym; wlasciwy limit to MinReplicas[s].
constraint forall(s in S, n in N)(x[s,n] <= MinReplicas[s]);

% 3. Rezerwa systemowa + aktualne pody + potencjalny burst nie moga
% przekraczac pojemnosci wlaczonego wezla. Gdy is_active=0, nie ma podow.
constraint forall(n in N, t in T)(
    sum(s in S)((x[s,n] + standby[s,n]) * Req[s,t])
        + SystemReserve[n,t] * is_active[n]
        <= NRes[n,t] * is_active[n]
);

% 4. Dla kazdej uslugi zapewnij mozliwie wiele miejsc na nowe repliki.
% shortage to miekkie naruszenie prognozowanego zapasu (nie obecnych SLA).
constraint forall(s in S)(
    sum(n in N)(standby[s,n]) + shortage[s] = BurstNeed[s]
);

% 5. Mozliwy wezel wymagany do utrzymania (np. stale potrzebny worker).
% Control plane zakladamy poza optymalizowanymi workerami.
constraint forall(n in N)(is_active[n] >= MustStayOn[n]);

% 6. Miekkie rozpraszanie replik. Druga i kolejne repliki na wezle
% zwiekszaja kare, ale pozostaja dozwolone.
constraint forall(s in S, n in N)(
    colocated[s,n] >= x[s,n] - 1
);

% Celowo NIE ma: sum(s)(x[s,n]) >= is_active[n].
% Dopuszczamy wlaczony, pusty wezel utrzymujacy gotowa pojemnosc.
% Sama dodatnia moc IdlePower sprawia, ze bez korzysci nie oplaca sie go wlaczyc.

% =====================================================================
% FUNKCJA CELU
% =====================================================================

% Moc calego wezla [W]. Zalozenie: requests CPU przyblizaja rzeczywisty load.
% RAM jest ograniczeniem, a nie dodatkowym skladnikiem dynamicznej mocy.
% IdlePower obejmuje bazowe zuzycie systemu i pamieci (bez podwojnego liczenia).
var float: total_power = sum(n in N)(
    int2float(IdlePower[n] * is_active[n])
    + int2float(MaxPower[n] - IdlePower[n])
      * int2float(used_cpu[n]) / int2float(NRes[n,CPU])
);

% Kary sa wyrazone w W-ekwiwalentach; NIE sa fizycznym poborem mocy.
var float: shortage_penalty =
    int2float(ShortagePenaltyMultiplier) / 100.0 *
    sum(s in S)(int2float(ShortagePenalty[s] * shortage[s]));

var float: spread_penalty =
    int2float(SpreadPenalty) * sum(s in S, n in N)(int2float(colocated[s,n]));

var float: total_objective = total_power + shortage_penalty + spread_penalty;

solve minimize total_objective;