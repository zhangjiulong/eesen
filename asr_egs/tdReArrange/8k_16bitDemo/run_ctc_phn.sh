#!/bin/bash

### for CMU rocks cluster ###
#PBS -q standard
#PBS -j oe
#PBS -o log
#PBS -d .
#PBS -V
#PBS -l walltime=48:00:00,nodes=1:ppn=12

. cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
         ## This relates to the queue.
. path.sh

stage=3

. parse_options.sh

if [ $stage -le 1 ]; then
  echo =====================================================================
  echo "             Data Preparation and FST Construction                 "
  echo =====================================================================
  # If you have downloaded the data (e.g., for Kaldi systems), then you can
  # simply link the db directory to here and skip this step
  # self prepare data do not download.
  #local/tedlium_download_data.sh || exit 1; 

  # Use the same data preparation script from Kaldi
  local/tedlium_prepare_data.sh || exit 11

  # Construct the phoneme-based lexicon
  local/tedlium_prepare_phn_dict.sh || exit 12;

  # Compile the lexicon and token FSTs
  utils/ctc_compile_dict_token.sh data/local/dict_phn data/local/lang_phn_tmp data/lang_phn || exit 13;

  # Compose the decoding graph
  local/tedlium_decode_graph.sh data/lang_phn || exit 14;
fi

if [ $stage -le 2 ]; then
  echo =====================================================================
  echo "                    FBank Feature Generation                       "
  echo =====================================================================
  fbankdir=fbank

  # Generate the fbank features; by default 40-dimensional fbanks on each frame
  for set in train test; do
    steps/make_fbank.sh --cmd "$train_cmd" --nj 20 data/$set exp/make_fbank/$set $fbankdir || exit 21;
    utils/fix_data_dir.sh data/$set || exit 22;
    steps/compute_cmvn_stats.sh data/$set exp/make_fbank/$set $fbankdir || exit 23;
  done

  # Split the whole training data into training (95%) and cross-validation (5%) sets
  utils/subset_data_dir_tr_cv.sh --cv-spk-percent 5 data/train data/train_tr95 data/train_cv05 || exit 24
fi

if [ $stage -le 3 ]; then
  echo =====================================================================
  echo "                Network Training with the 110-Hour Set             "
  echo =====================================================================
  # Specify network structure and generate the network topology
  input_feat_dim=120   # dimension of the input features; we will use 40-dimensional fbanks with deltas and double deltas
  lstm_layer_num=5     # number of LSTM layers
  lstm_cell_dim=320    # number of memory cells in every LSTM layer

  dir=exp/train_phn_l${lstm_layer_num}_c${lstm_cell_dim}
  mkdir -p $dir

  target_num=`cat data/lang_phn/units.txt | wc -l`; target_num=$[$target_num+1]; #  #targets = #labels + 1 (the blank)

  # Output the network topology
  utils/model_topo.py --input-feat-dim $input_feat_dim --lstm-layer-num $lstm_layer_num \
    --lstm-cell-dim $lstm_cell_dim --target-num $target_num \
    --fgate-bias-init 1.0 > $dir/nnet.proto || exit 31;

  # Label sequences; simply convert words into their label indices
  utils/prep_ctc_trans.py data/lang_phn/lexicon_numbers.txt data/train_tr95/text "<UNK>" | gzip -c - > $dir/labels.tr.gz
  utils/prep_ctc_trans.py data/lang_phn/lexicon_numbers.txt data/train_cv05/text "<UNK>" | gzip -c - > $dir/labels.cv.gz

  # Train the network with CTC. Refer to the script for details about the arguments
  steps/train_ctc_parallel.sh --add-deltas true --num-sequence 10 --frame-num-limit 15000 \
    --learn-rate 0.00004 --report-step 1000 --halving-after-epoch 12 \
    --feats-tmpdir $dir/XXXXX \
    data/train_tr95 data/train_cv05 $dir || exit 32;

  echo =====================================================================
  echo "                            Decoding                               "
  echo =====================================================================
  # decoding
  # steps/decode_ctc_lat.sh --cmd "$decode_cmd" --nj 8 --beam 17.0 --lattice_beam 8.0 --max-active 5000 --acwt 0.6 \
  # data/lang_phn_test data/test $dir/decode_dev || exit 33;
  steps/decode_ctc_lat.sh --cmd "$decode_cmd" --nj 11 --beam 17.0 --lattice_beam 8.0 --max-active 10000 --acwt 0.6 \
    data/lang_phn_test data/test $dir/decode_test || exit 34;
fi
