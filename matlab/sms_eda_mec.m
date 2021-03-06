function [final_pareto_front, ...   % objectives
          final_pareto_set ...      % parameters
         ] = sms_eda_mec(problem, inopts)
% Reference implementation for the S-Metric Selection Estimation of Distribution Algorithm based on
% Multivariate Extension of Copulas (SMS-EDA-MEC).
%
% Luis Marti, Harold D. de Mello Jr., Nayat Sanchez-Pi and Marley Vellasco (2016)
% SMS-EDA-MEC: Extending Copula-based EDAs to Multi-Objective Optimization,
% 2016 IEEE Conference on Evolutionary Computation (CEC'2016), part of the
% 2016 IEEE World Congress on Computational Intelligence (WCCI'2016),
% Vancouver, Canada, pp. 3726--3733. doi: 10.1109/CEC.2016.7744261.
%
% sms_eda_mec(problem_name, options):
%    runs SMS-EDA-MEC on problem_name, options not especified will use the default values.
% sms_eda_mec():
%    prints the options and their default values.
%
% Check https://github.com/lmarti/sms-eda-mec for updates.

% ----------- Set Defaults for Options ---------------------------------
% options: general - these are evaluated once
defopts.pop_size           = '100           % size of the population';
defopts.num_offspring      = '100           % number of offspring individuals to generate';
defopts.maxEval            = '10000         % maximum number of evaluations';
defopts.OCD_VarLimit       = '1e-4          % variance limit of OCD';
defopts.OCD_nPreGen        = '10            % number of preceding generations used in OCD';
defopts.nPFevalHV          = 'inf           % evaluate 1st to this number paretoFronts with HV';
defopts.outputGen          = 'inf           % rate of writing output files';
defopts.refPoint           = '0             % refPoint for HV; if 0, max(obj)+1 is used';
defopts.n_precursors       = '10            % number of precursors';
defopts.copula_type        = 'EDAMEC        % copula types {Gaussian|t|Clayton|Frank|Gumbel|EDAMEC}';
defopts.do_restarting      = 'true          % use restarting?';
defopts.restart_gap        = 'true          % number of iterations to wait between restarts';
defopts.restarting_percent = '0.9           % enable restarting only in the part of the evolution';
defopts.base_kl            = '0.15          % ';
defopts.show_plots         = 'false         % show interactive progress plots';

% ---------------------- Handling Input Parameters ----------------------

if nargin < 1 || isequal(problem, 'defaults') % pass default options
    if nargin < 1
        disp('Default options returned (type "help sms_eda_mec" for help).');
    end
    final_pareto_front = defopts;
    if nargin > 1 % supplement second argument with default options
        final_pareto_front = getoptions(inopts, defopts);
    end
    return;
end

% Reset the random number generator to a different state each restart
rand('state', sum(100*clock));


% load parameters from problem
if strfind(problem, 'WFG')
    [num_vars, rng_min, rng_max isInt, num_objs, problem_func] = initializeWFG(problem(4));
else
    initProblemStr = sprintf('initialize%s', problem);
    [num_vars, rng_min, rng_max, isInt, num_objs, problem_func] = feval(initProblemStr);
end

if isequal(problem, 'displayoptions')
    names = fieldnames(defopts);
    for name = names'
        disp([name{:} repmat(' ', 1, 20-length(name{:})) ': ''' defopts.(name{:}) '''']);
    end
    return;
end

if isempty(problem)
    error('Objective function not determined');
end
if ~ischar(problem)
    error('first argument ''problem'' must be a string');
end

% Compose options opts
if nargin < 2 || isempty(inopts) % no input options available
    opts = defopts;
else
    opts = getoptions(inopts, defopts);
end

% get parameters for initialization
pop_size = myeval(opts.pop_size);

max_eval = myeval(opts.maxEval);
OCD_VarLimit = myeval(opts.OCD_VarLimit);
OCD_nPreGen = myeval(opts.OCD_nPreGen);
nPFevalHV = myeval(opts.nPFevalHV);
outputGen = myeval(opts.outputGen);

refPoint = myeval(opts.refPoint);

base_kl = myeval(opts.base_kl);

copula_type = myeval(opts.copula_type);

do_restarting = myeval(opts.do_restarting);
restart_gap = myeval(opts.restart_gap);
restarting_percent = myeval(opts.restarting_percent);

n_precursors = myeval(opts.n_precursors);

num_offspring = myeval(opts.num_offspring);

show_plots = myeval(opts.show_plots);

if show_plots == true
    close();
end

% initial population - every row an individual
pop = generate_random_population(pop_size, num_vars, rng_min, rng_max);   % dist uniforme
pop_obj = problem_func(pop);

% set evaluation counter
count_eval = pop_size;

PF{1} = pop_obj(paretofront(pop_obj));

iteration = 0;
restart_count = 0;
restart_iteration = 1;
kl = base_kl;

% we have to find a better solution later on
global theta momentum
momentum = 0.01;
theta = NaN;

while count_eval < max_eval
    iteration = iteration + 1;

    if mod(iteration, 10) == 0
        fprintf('Iteration: %d; evals: %d.\n', iteration, count_eval);
        fprintf('%d percent calculated.\n', floor((count_eval./(max_eval-1))*100));
    end;

    if do_restarting && count_eval/max_eval <= restarting_percent
        ranks = paretoRank(pop_obj);
        %
        stagnation_criterion = false;

        if (iteration > OCD_nPreGen+1)
            for i = 2:OCD_nPreGen+1
                PF{i-1} = PF{i};
            end;
            PF{OCD_nPreGen+1} = pop_obj(ranks==1,:);
            [OCD_termCrit OCD_lb OCD_ub OCD_pChi2 OCD_pReg] = OCD(PF, ...
                OCD_VarLimit, 0.05, [1 1 1], ...
                OCD_lb, OCD_ub, OCD_pChi2, OCD_pReg);
            %fprintf('%d evaluations calculated\n', count_eval);
            %fprintf('maximum p-value variance test: %f\n', max(OCD_pChi2));
            %fprintf('p-value regression analysis: %f\n', OCD_pReg);
        else
            PF{iteration} = pop_obj(ranks==1,:);
            if iteration == OCD_nPreGen+1
                [OCD_termCrit OCD_lb OCD_ub OCD_pChi2 OCD_pReg] = OCD(PF,...
                    OCD_VarLimit);
                %fprintf('%d evaluations calculated\n', count_eval);
                %fprintf('maximum p-value variance test: %f\n', max(OCD_pChi2));
                %fprintf('p-value regression analysis: %f\n', OCD_pReg);
            end
        end

        if exist('OCD_termCrit', 'var') && any(OCD_termCrit)
            stagnation_criterion = any(OCD_termCrit);
            if OCD_termCrit(1)
                fprintf('OCD detected convergence due to the variance test\n');
            else
                fprintf('OCD detected convergence due to the regression analysis\n');
            end
        end

        % avoid continuous restarting and restarting in the final part of the
        % evolution

        % is restaring needed?
        if stagnation_criterion && iteration - restart_iteration > restart_gap
            fprintf('Restarting population...\n');

            max_pop = max(pop);
            min_pop = min(pop);

            restart_count = restart_count + 1;
            restart_iteration = iteration;

            pop_local_restarted  = generate_random_population(pop_size, num_vars, min_pop, max_pop);
            pop_global_restarted = generate_random_population(pop_size, num_vars, rng_min, rng_max);

            pop(1:floor(pop_size*kl),:) = pop_local_restarted(1:floor(pop_size*kl),:);
            pop(end-floor(pop_size*kl):end,:) = pop_global_restarted(end-floor(pop_size*kl):end,:);

            if restart_count > 1
                kl = kl/2;
                if kl < 0.05
                    kl = base_kl;
                end
            end

            pop_obj = problem_func(pop);
            count_eval = count_eval + size(pop_obj,1);
        end
    end
    % -- end of restart

    % -- computing copula and new individuals
    offspring = generate_copula_indivuduals(copula_type, pop, num_offspring);
    offspring = enforce_domain(offspring, rng_min, rng_max);

    offspring_obj = problem_func(offspring);

    count_eval = count_eval + num_offspring;

    if n_precursors > 0
        rebel_pop = compute_rebels(pop, pop_obj, n_precursors, nPFevalHV, refPoint);
        rebel_pop_obj = problem_func(rebel_pop);
        count_eval = count_eval + n_precursors;
    else
        rebel_pop = [];
        rebel_pop_obj = [];
    end

    %% -- plots for assessing diversity
    if show_plots == true && (mod(iteration,1) == 0 || iteration == 1 || restart_iteration == iteration)
       if num_vars == 2
           subplot(2,1,1);
           hold off;
           plot(pop(:,1),pop(:,2), 'bo');
           hold on;
           plot(offspring(:,1),offspring(:,2), 'r.');
           plot(rebel_pop(:,1), rebel_pop(:,2), 'g*');
           title(strcat('Search space - parents blue; offspring red - t=', num2str(iteration)));
           subplot(2,1,2);
       end
       hold off;
       plot(pop_obj(:,1), pop_obj(:,2), 'bo');
       hold on;
       plot(offspring_obj(:,1), offspring_obj(:,2), 'r.');
       plot(rebel_pop_obj(:,1), rebel_pop_obj(:,2), 'g*');
       title(strcat('Objectives -  parents blue; offspring red - t=', num2str(iteration)));
       drawnow;
    end

    total_pop = [pop; offspring];
    total_pop_obj = [pop_obj; offspring_obj];

    while size(total_pop,1) > pop_size - n_precursors
        ranks = paretoRank(total_pop_obj);
        nPV = max(ranks);
        elementInd = select_element_to_remove(total_pop, total_pop_obj, pop_size, num_objs, ...
            num_vars, nPV, ranks, nPFevalHV, refPoint);
        total_pop(elementInd,:) = [];
        total_pop_obj(elementInd,:) = [];
    end

    total_pop = [total_pop; rebel_pop];
    total_pop_obj = [total_pop_obj;rebel_pop_obj];

    perm = randperm(pop_size);

    pop = total_pop(perm,:);
    pop_obj = total_pop_obj(perm,:);
end

final_front_mask =  paretofront(pop_obj);
final_pareto_front = pop_obj(final_front_mask,:);
final_pareto_set = pop(final_front_mask,:);
hold off;
end

function res = scale_up(pop, rng_min, rng_max)
[rows, cols] = size(pop);
res = zeros(rows,cols);
shifts = (rng_max - rng_min);
for col = 1:cols
    res(:,col) = pop(:,col) * shifts(col) + rng_min(col);
end
end

function res = scale_down(pop, rng_min, rng_max)
[rows, cols] = size(pop);
res = zeros(rows,cols);
shifts = (rng_max - rng_min);
for col = 1:cols
    res(:,col) = (pop(:,col) - rng_min(col)) / shifts(col) ;
end
end

function rebel_pop = compute_rebels(pop, pop_obj, n_precursors, nPFevalHV, refPoint)
global theta
[pop_size, num_vars] = size(pop);
num_objs = size(pop_obj,2);

ranks = paretoRank(pop_obj);

best_subset = [];
best_subset_obj = [];

rank_index = 0;
while size(best_subset,1) < floor(0.3 * size(pop,1))
    rank_index = rank_index + 1;
    best_subset = [best_subset; pop(ranks==rank_index,:)];
    best_subset_obj = [best_subset_obj; pop_obj(ranks==rank_index,:)];
end

fprintf('Ranks reached %d, total: %d, subset size before pruning: %d.\n', rank_index, max(ranks), size(best_subset,1));

while size(best_subset,1) > floor(0.3 * size(pop,1))
    ranks = paretoRank(best_subset_obj);
    nPV = max(ranks);
    elementInd = select_element_to_remove(best_subset, best_subset_obj, pop_size, num_objs, ...
        num_vars, nPV, ranks, nPFevalHV, refPoint);
    best_subset(elementInd,:) = [];
    best_subset_obj(elementInd,:) = [];
end

best_min = min(best_subset);
best_max = max(best_subset);

best_subset = scale_down(best_subset, best_min, best_max);

[idd, idx] = sort(clayton_cop(best_subset, size(best_subset,1), theta)); % nao funciona
u2 = 1-idd;

if size(best_subset,1) == 1
    data = best_subset;
else
    data = best_subset(idx);
end

y_inv = zeros(size(best_subset,1), num_vars);

for k=1:num_vars
    y_inv(:,k) = quantile(data(:,k), u2(:,k));
end

rebel_cdf_direta = y_inv;
rebel_cdf_inversa = flipud(y_inv);

% perm = randperm(size(best_subset,1));
% rebel_cdf_direta = rebel_cdf_direta(perm, :);
% rebel_cdf_inversa = rebel_cdf_inversa(perm, :);

part_size = floor(n_precursors/2);

rebel_pop = [rebel_cdf_direta(1:part_size,:); rebel_cdf_inversa(1:part_size,:)];

% rebel_pop = rebel_cdf_inversa(1:n_precursors,:);

rebel_pop = scale_up(rebel_pop, best_min, best_max);
end

function offspring=copula_edamec(pop, num_offspring)
global momentum theta
num_vars = size(pop,2);

mat_tau = corr(pop, 'type', 'Kendall');
tau = sum(sum(triu(mat_tau,1)))/((num_vars^2-num_vars)/2);

if isnan(theta)
    theta = 2*tau/(1-tau);
else
    theta = (1 - momentum) * 2*tau/(1-tau) + momentum * theta;
end

if theta < 10^-4
    theta = 1.0e-4; %0.2+rand; %0.1;%+rand;
end

u1 = clayton_cop(pop, num_offspring, theta);

marg = 1;

offspring = zeros(num_offspring, num_vars);
%C Computing new individuals
if marg == 1
    % Normal Marginal Distributions
    upperx = max(pop);
    lowerx = min(pop);
    y = norminv(u1,0,1);
    for k= 1:num_offspring
        offspring(k,:) = y(k,:).*(upperx-lowerx)+lowerx;
    end
else
    % Empirical Marginal Distributions
    for k= 1:num_vars
        offspring(:,k) = quantile(offspring(:, k), u1(:,k));
    end
end
end

function [w] = clayton_cop(data, np, theta)
%% samples the Clayton's copula
w= zeros(np,size(data,2));
w(:,1)= rand(np,1);

for j=2:size(data,2)
  for i=1:np
    t=rand;
    w(i,j)= ((sum(w(i,1:j-1).^-theta)-j+2).*(t.^(theta/(theta*(1-j)-1))-1) +1).^(-1/theta);
  end
end
end

function offspring=generate_copula_indivuduals(copula_type, pop, num_offspring)
epsilon = 0.0000000001;
pop_min = min(pop) - epsilon;
pop_max = max(pop) + epsilon;
scaled = scale_down(pop, pop_min, pop_max);
if strcmp(copula_type, 'Gaussian')
    rho_hat = copulafit('Gaussian', scaled);
    offspring = copularnd('Gaussian', rho_hat, num_offspring);
elseif strcmp(copula_type, 't')
    [rho_hat,nu_hat] = copulafit('t', scaled);
    offspring = copularnd('t', rho_hat, nu_hat, num_offspring);
elseif strcmp(copula_type, 'Clayton') || strcmp(copula_type, 'Frank') || strcmp(copula_type, 'Gumbel')
    param_hat = copulafit(copula_type, scaled, 'Alpha', 0.01);
    offspring = copularnd(copula_type, param_hat, num_offspring);
elseif strcmp(copula_type, 'EDAMEC')
    offspring = copula_edamec(scaled, num_offspring);
end

offspring = scale_up(offspring, pop_min, pop_max);
end

%%-------------------------------------------------------------------------
function opts=getoptions(inopts, defopts)
% OPTS = GETOPTIONS(INOPTS, DEFOPTS) handles an arbitrary number of
% optional arguments to a function. The given arguments are collected
% in the struct INOPTS.  GETOPTIONS matches INOPTS with a default
% options struct DEFOPTS and returns the merge OPTS.  Empty or missing
% fields in INOPTS invoke the default value.  Fieldnames in INOPTS can
% be abbreviated.
if nargin < 2 || isempty(defopts) % no default options available
    opts=inopts;
    return;
elseif isempty(inopts) % empty inopts invoke default options
    opts = defopts;
    return;
elseif ~isstruct(defopts) % handle a single option value
    if isempty(inopts)
        opts = defopts;
    elseif ~isstruct(inopts)
        opts = inopts;
    else
        error('Input options are a struct, while default options are not');
    end
    return;
elseif ~isstruct(inopts) % no valid input options
    error('The options need to be a struct or empty');
end

opts = defopts; % start from defopts
% if necessary overwrite opts fields by inopts values
defnames = fieldnames(defopts);
idxmatched = []; % indices of defopts that already matched
for name = fieldnames(inopts)'
    name = name{1}; % name of i-th inopts-field
    idx = strncmpi(defnames, name, length(name));
    if sum(idx) > 1
        error(['option "' name '" is not an unambigous abbreviation. ' ...
            'Use opts=RMFIELD(opts, ''' name, ...
            ''') to remove the field from the struct.']);
    end
    if sum(idx) == 1
        defname  = defnames{find(idx)};
        if ismember(find(idx), idxmatched)
            error(['input options match more than ones with "' ...
                defname '". ' ...
                'Use opts=RMFIELD(opts, ''' name, ...
                ''') to remove the field from the struct.']);
        end
        idxmatched = [idxmatched find(idx)];
        val = getfield(inopts, name);
        % next line can replace previous line from MATLAB version 6.5.0 on and in octave
        % val = inopts.(name);
        if isstruct(val) % valid syntax only from version 6.5.0
            opts = setfield(opts, defname, ...
                getoptions(val, getfield(defopts, defname)));
        elseif isstruct(getfield(defopts, defname))
            % next three lines can replace previous three lines from MATLAB
            % version 6.5.0 on
            %   opts.(defname) = ...
            %      getoptions(val, defopts.(defname));
            % elseif isstruct(defopts.(defname))
            warning(['option "' name '" disregarded (must be struct)']);
        elseif ~isempty(val) % empty value: do nothing, i.e. stick to default
            opts = setfield(opts, defnames{find(idx)}, val);
            % next line can replace previous line from MATLAB version 6.5.0 on
            % opts.(defname) = inopts.(name);
        end
    else
        warning(['option "' name '" disregarded (unknown field name)']);
    end
end
end

%%-------------------------------------------------------------------------
function res=myeval(s)
if ischar(s)
    try
        res = evalin('caller', s);
    catch e
        s1 = strcat(s,'');
        res = strtrim(s1(1:strfind(s1, '%')-1));
    end
else
    res = s;
end
end

function out_pop = enforce_domain(in_pop, rng_min, rng_max)
[n_inds, n_vars] = size(in_pop);
out_pop = zeros(n_inds, n_vars);
for k=1:n_vars
    out_pop(:,k) = min(max(in_pop(:,k), rng_min(k)), rng_max(k));
end
end

function pop = generate_random_population(pop_size, num_vars, rng_min, rng_max)
pop = rand(pop_size, num_vars);
pop = scale_up(pop, rng_min, rng_max);
end

function elementInd = select_element_to_remove(population, pop_obj, nPop ,nObj, ...
    nVar, nPV, ranks, nPFevalHV, refPoint)
if nPV > nPFevalHV
    elementsInd = find(ranks==nPV);
    frontsize = size(elementsInd,1);
    % remove random element
    elementInd = ceil(rand(1)*frontsize);
    if elementInd == 0
        elementInd=1;
    end
else
    % use HV
    elementsInd = find(ranks==nPV);
    frontsize = size(elementsInd,1);
    if frontsize==1
        elementInd = 1;
    else
        frontObjectives = pop_obj(elementsInd,:);
        if refPoint==0
            refPoint = max(frontObjectives)+1;
        else
            index = false(frontsize,1);
            for i = 1:frontsize
                if sum(frontObjectives(i,:) >= refPoint) > 0
                    index(i) = true;
                end;
            end;
            if sum(index) > 0
                [maxVal, IX] = max(max(frontObjectives-...
                    repmat(refPoint,frontsize,1), [], 2));
                elementInd = elementsInd(IX(1));
                return;
            end;
        end
        if nObj == 2
            [frontObjectives IX] = sortrows(frontObjectives, 1);
            deltaHV(IX(1)) = ...
                (frontObjectives(2,1) - frontObjectives(1,1)) .* ...
                (refPoint(2) - frontObjectives(1,2));
            for i = 2:frontsize-1
                deltaHV(IX(i)) = ...
                    (frontObjectives(i+1,1) - frontObjectives(i,1))...
                    .* ...
                    (frontObjectives(i-1,2) - frontObjectives(i,2));
            end;
            deltaHV(IX(frontsize)) = ...
                (refPoint(1) - frontObjectives(frontsize,1)) .* ...
                (frontObjectives(frontsize-1,2) - ...
                frontObjectives(frontsize,2));
        else
            currentHV = hv(frontObjectives', refPoint);
            deltaHV = zeros(1,frontsize);
            for i=1:frontsize
                myObjectives = frontObjectives;
                myObjectives(i,:)=[];
                myHV = hv(myObjectives', refPoint);
                deltaHV(i) = currentHV - myHV;
            end
        end
        [deltaHV,IX]=min(deltaHV);
        elementInd = IX(1);
    end
end
elementInd = elementsInd(elementInd);
end
