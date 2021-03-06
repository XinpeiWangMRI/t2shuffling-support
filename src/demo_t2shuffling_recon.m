%%%%%%
% T2 Shuffling Demo: Perform a T2 Shuffling reconstruction.
% The code is provided to demonstrate the method. It is not optimized
% for reconstruction time.
%
% Jonathan Tamir <jtamir@eecs.berkeley.edu>
% Jan 04, 2016
%
%%
addpath src/utils
%% load data

sens1 = squeeze(readcfl('data/knee/sens'));
bas = squeeze(readcfl('data/knee/bas'));
mask = squeeze(readcfl('data/knee/mask'));
ksp = squeeze(readcfl('data/knee/ksp.te'));

% parameters
K = 4;

[ny, nz, nc, T] = size(ksp);

% subspace
Phi = bas(:,1:K);

% permute mask
masks = permute(mask, [1 2 4 3]);

% normalize sensitivities
sens1_mag = reshape(vecnorm(reshape(sens1, [], nc).'), [ny, nz]);
sens = bsxfun(@rdivide, sens1, sens1_mag);
sens(isnan(sens)) = 0;

%% operators

% ESPIRiT maps operator applied to coefficient images
S_for = @(a) bsxfun(@times, sens, permute(a, [1, 2, 4, 3]));
S_adj = @(as) squeeze(sum(bsxfun(@times, conj(sens), as), 3));
SHS = @(a) S_adj(S_for(a));

% Temporal projection operator
T_for = @(a) temporal_forward(a, Phi);
T_adj = @(x) temporal_adjoint(x, Phi);

% Fourier transform
F_for = @(x) fft2c(x);
F_adj = @(y) ifft2c(y);

% Sampling mask
P_for = @(y) bsxfun(@times, y, masks);

% Full forward model
A_for = @(a) P_for(T_for(F_for(S_for(a))));
A_adj = @(y) S_adj(F_adj(T_adj(P_for(y))));
AHA = @(a) S_adj(F_adj(T_adj(P_for(T_for(F_for(S_for(a))))))); % slightly faster


% ksp = P_for(F_for(S_for(im_truth)));

%% scaling
tmp = dimnorm(ifft2c(bsxfun(@times, ksp, masks)), 3);
tmpnorm = dimnorm(tmp, 4);
tmpnorm2 = sort(tmpnorm(:), 'ascend');
% match convention used in BART
p100 = tmpnorm2(end);
p90 = tmpnorm2(round(.9 * length(tmpnorm2)));
p50 = tmpnorm2(round(.5 * length(tmpnorm2)));
if (p100 - p90) < 2 * (p90 - p50)
    scaling = p90;
else
    scaling = p100;
end
fprintf('\nScaling: %f\n\n', scaling);

ksp = ksp ./ scaling;
ksp_adj = A_adj(ksp);

%% ADMM

iter_ops.max_iter = 200;
iter_ops.rho = .1;
iter_ops.objfun = @(a, sv, lam) 0.5*norm_mat(ksp - A_for(a))^2 + lam*sum(sv(:));

llr_ops.lambda = .04;
llr_ops.block_dim = [10, 10];

lsqr_ops.max_iter = 10;
lsqr_ops.tol = 1e-4;

alpha_ref = RefValue;
alpha_ref.data = zeros(ny, nz, K);

history = iter_admm(alpha_ref, iter_ops, llr_ops, lsqr_ops, AHA, ksp_adj, @admm_callback);

disp(' ');

%% Project and re-scale
alpha = alpha_ref.data;
im = T_for(alpha);

disp('Rescaling')
im = im * scaling;

%% Show the result
figure(1), plot(1:history.nitr, history.objval, 'linewidth', 3);
ftitle('Objective Value vs. Iteration Number'); xlabel('Iteration Number');
ylabel('Objective Value'); faxis;

figure(2);
imshow(abs(reshape(alpha, ny, [])), []);
ftitle('Reconstructed Coefficient Images');

figure(3);
imshow(abs(cat(2, im(:,:,5), im(:,:,15), im(:,:,30))), []);
ftitle('Reconstruction at TE # 5, 15, and 30');




