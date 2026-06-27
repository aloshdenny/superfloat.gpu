module systolic_pe (clear_acc,
    clk,
    compute_enable,
    enable,
    load_weight,
    reset,
    a_in,
    a_out,
    acc_out,
    b_in,
    b_out);
 input clear_acc;
 input clk;
 input compute_enable;
 input enable;
 input load_weight;
 input reset;
 input [15:0] a_in;
 output [15:0] a_out;
 output [15:0] acc_out;
 input [15:0] b_in;
 output [15:0] b_out;

 wire _0000_;
 wire _0001_;
 wire _0002_;
 wire _0003_;
 wire _0004_;
 wire _0005_;
 wire _0006_;
 wire _0007_;
 wire _0008_;
 wire _0009_;
 wire _0010_;
 wire _0011_;
 wire _0012_;
 wire _0013_;
 wire _0014_;
 wire _0015_;
 wire _0016_;
 wire _0017_;
 wire _0018_;
 wire _0019_;
 wire _0020_;
 wire _0021_;
 wire _0022_;
 wire _0023_;
 wire _0024_;
 wire _0025_;
 wire _0026_;
 wire _0027_;
 wire _0028_;
 wire _0029_;
 wire _0030_;
 wire _0031_;
 wire _0032_;
 wire _0033_;
 wire _0034_;
 wire _0035_;
 wire _0036_;
 wire _0037_;
 wire _0038_;
 wire _0039_;
 wire _0040_;
 wire _0041_;
 wire _0042_;
 wire _0043_;
 wire _0044_;
 wire _0045_;
 wire _0046_;
 wire _0047_;
 wire _0048_;
 wire _0049_;
 wire _0050_;
 wire _0051_;
 wire _0052_;
 wire _0053_;
 wire _0054_;
 wire _0055_;
 wire _0056_;
 wire _0057_;
 wire _0058_;
 wire _0059_;
 wire _0060_;
 wire _0061_;
 wire _0062_;
 wire _0063_;
 wire _0064_;
 wire _0065_;
 wire _0066_;
 wire _0067_;
 wire _0068_;
 wire _0069_;
 wire _0070_;
 wire _0071_;
 wire _0072_;
 wire _0073_;
 wire _0074_;
 wire _0075_;
 wire _0076_;
 wire _0077_;
 wire _0078_;
 wire _0079_;
 wire _0080_;
 wire _0081_;
 wire _0082_;
 wire _0083_;
 wire _0084_;
 wire _0085_;
 wire _0086_;
 wire _0087_;
 wire _0088_;
 wire _0089_;
 wire _0090_;
 wire _0091_;
 wire _0092_;
 wire _0093_;
 wire _0094_;
 wire _0095_;
 wire _0096_;
 wire _0097_;
 wire _0098_;
 wire _0099_;
 wire _0100_;
 wire _0101_;
 wire _0102_;
 wire _0103_;
 wire _0104_;
 wire _0105_;
 wire _0106_;
 wire _0107_;
 wire _0108_;
 wire _0109_;
 wire _0110_;
 wire _0111_;
 wire _0112_;
 wire _0113_;
 wire _0114_;
 wire _0115_;
 wire _0116_;
 wire _0117_;
 wire _0118_;
 wire _0119_;
 wire _0120_;
 wire _0121_;
 wire _0122_;
 wire _0123_;
 wire _0124_;
 wire _0125_;
 wire _0126_;
 wire _0127_;
 wire _0128_;
 wire _0129_;
 wire _0130_;
 wire _0131_;
 wire _0132_;
 wire _0133_;
 wire _0134_;
 wire _0135_;
 wire _0136_;
 wire _0137_;
 wire _0138_;
 wire _0139_;
 wire _0140_;
 wire _0141_;
 wire _0142_;
 wire _0143_;
 wire _0144_;
 wire _0145_;
 wire _0146_;
 wire _0147_;
 wire _0148_;
 wire _0149_;
 wire _0150_;
 wire _0151_;
 wire _0152_;
 wire _0153_;
 wire _0154_;
 wire _0155_;
 wire _0156_;
 wire _0157_;
 wire _0158_;
 wire _0159_;
 wire _0160_;
 wire _0161_;
 wire _0162_;
 wire _0163_;
 wire _0164_;
 wire _0165_;
 wire _0166_;
 wire _0167_;
 wire _0168_;
 wire _0169_;
 wire _0170_;
 wire _0171_;
 wire _0172_;
 wire _0173_;
 wire _0174_;
 wire _0175_;
 wire _0176_;
 wire _0177_;
 wire _0178_;
 wire _0179_;
 wire _0180_;
 wire _0181_;
 wire _0182_;
 wire _0183_;
 wire _0184_;
 wire _0185_;
 wire _0186_;
 wire _0187_;
 wire _0188_;
 wire _0189_;
 wire _0190_;
 wire _0191_;
 wire _0192_;
 wire _0193_;
 wire _0194_;
 wire _0195_;
 wire _0196_;
 wire _0197_;
 wire _0198_;
 wire _0199_;
 wire _0200_;
 wire _0201_;
 wire _0202_;
 wire _0203_;
 wire _0204_;
 wire _0205_;
 wire _0206_;
 wire _0207_;
 wire _0208_;
 wire _0209_;
 wire _0210_;
 wire _0211_;
 wire _0212_;
 wire _0213_;
 wire _0214_;
 wire _0215_;
 wire _0216_;
 wire _0217_;
 wire _0218_;
 wire _0219_;
 wire _0220_;
 wire _0221_;
 wire _0222_;
 wire _0223_;
 wire _0224_;
 wire _0225_;
 wire _0226_;
 wire _0227_;
 wire _0228_;
 wire _0229_;
 wire _0230_;
 wire _0231_;
 wire _0232_;
 wire _0233_;
 wire _0234_;
 wire _0235_;
 wire _0236_;
 wire _0237_;
 wire _0238_;
 wire _0239_;
 wire _0240_;
 wire _0241_;
 wire _0242_;
 wire _0243_;
 wire _0244_;
 wire _0245_;
 wire _0246_;
 wire _0247_;
 wire _0248_;
 wire _0249_;
 wire _0250_;
 wire _0251_;
 wire _0252_;
 wire _0253_;
 wire _0254_;
 wire _0255_;
 wire _0256_;
 wire _0257_;
 wire _0258_;
 wire _0259_;
 wire _0260_;
 wire _0261_;
 wire _0262_;
 wire _0263_;
 wire _0264_;
 wire _0265_;
 wire _0266_;
 wire _0267_;
 wire _0268_;
 wire _0269_;
 wire _0270_;
 wire _0271_;
 wire _0272_;
 wire _0273_;
 wire _0274_;
 wire _0275_;
 wire _0276_;
 wire _0277_;
 wire _0278_;
 wire _0279_;
 wire _0280_;
 wire _0281_;
 wire _0282_;
 wire _0283_;
 wire _0284_;
 wire _0285_;
 wire _0286_;
 wire _0287_;
 wire _0288_;
 wire _0289_;
 wire _0290_;
 wire _0291_;
 wire _0292_;
 wire _0293_;
 wire _0294_;
 wire _0295_;
 wire _0296_;
 wire _0297_;
 wire _0298_;
 wire _0299_;
 wire _0300_;
 wire _0301_;
 wire _0302_;
 wire _0303_;
 wire _0304_;
 wire _0305_;
 wire _0306_;
 wire _0307_;
 wire _0308_;
 wire _0309_;
 wire _0310_;
 wire _0311_;
 wire _0312_;
 wire _0313_;
 wire _0314_;
 wire _0315_;
 wire _0316_;
 wire _0317_;
 wire _0318_;
 wire _0319_;
 wire _0320_;
 wire _0321_;
 wire _0322_;
 wire _0323_;
 wire _0324_;
 wire _0325_;
 wire _0326_;
 wire _0327_;
 wire _0328_;
 wire _0329_;
 wire _0330_;
 wire _0331_;
 wire _0332_;
 wire _0333_;
 wire _0334_;
 wire _0335_;
 wire _0336_;
 wire _0337_;
 wire _0338_;
 wire _0339_;
 wire _0340_;
 wire _0341_;
 wire _0342_;
 wire _0343_;
 wire _0344_;
 wire _0345_;
 wire _0346_;
 wire _0347_;
 wire _0348_;
 wire _0349_;
 wire _0350_;
 wire _0351_;
 wire _0352_;
 wire _0353_;
 wire _0354_;
 wire _0355_;
 wire _0356_;
 wire _0357_;
 wire _0358_;
 wire _0359_;
 wire _0360_;
 wire _0361_;
 wire _0362_;
 wire _0363_;
 wire _0364_;
 wire _0365_;
 wire _0366_;
 wire _0367_;
 wire _0368_;
 wire _0369_;
 wire _0370_;
 wire _0371_;
 wire _0372_;
 wire _0373_;
 wire _0374_;
 wire _0375_;
 wire _0376_;
 wire _0377_;
 wire _0378_;
 wire _0379_;
 wire _0380_;
 wire _0381_;
 wire _0382_;
 wire _0383_;
 wire _0384_;
 wire _0385_;
 wire _0386_;
 wire _0387_;
 wire _0388_;
 wire _0389_;
 wire _0390_;
 wire _0391_;
 wire _0392_;
 wire _0393_;
 wire _0394_;
 wire _0395_;
 wire _0396_;
 wire _0397_;
 wire _0398_;
 wire _0399_;
 wire _0400_;
 wire _0401_;
 wire _0402_;
 wire _0403_;
 wire _0404_;
 wire _0405_;
 wire _0406_;
 wire _0407_;
 wire _0408_;
 wire _0409_;
 wire _0410_;
 wire _0411_;
 wire _0412_;
 wire _0413_;
 wire _0414_;
 wire _0415_;
 wire _0416_;
 wire _0417_;
 wire _0418_;
 wire _0419_;
 wire _0420_;
 wire _0421_;
 wire _0422_;
 wire _0423_;
 wire _0424_;
 wire _0425_;
 wire _0426_;
 wire _0427_;
 wire _0428_;
 wire _0429_;
 wire _0430_;
 wire _0431_;
 wire _0432_;
 wire _0433_;
 wire _0434_;
 wire _0435_;
 wire _0436_;
 wire _0437_;
 wire _0438_;
 wire _0439_;
 wire _0440_;
 wire _0441_;
 wire _0442_;
 wire _0443_;
 wire _0444_;
 wire _0445_;
 wire _0446_;
 wire _0447_;
 wire _0448_;
 wire _0449_;
 wire _0450_;
 wire _0451_;
 wire _0452_;
 wire _0453_;
 wire _0454_;
 wire _0455_;
 wire _0456_;
 wire _0457_;
 wire _0458_;
 wire _0459_;
 wire _0460_;
 wire _0461_;
 wire _0462_;
 wire _0463_;
 wire _0464_;
 wire _0465_;
 wire _0466_;
 wire _0467_;
 wire _0468_;
 wire _0469_;
 wire _0470_;
 wire _0471_;
 wire _0472_;
 wire _0473_;
 wire _0474_;
 wire _0475_;
 wire _0476_;
 wire _0477_;
 wire _0478_;
 wire _0479_;
 wire _0480_;
 wire _0481_;
 wire _0482_;
 wire _0483_;
 wire _0484_;
 wire _0485_;
 wire _0486_;
 wire _0487_;
 wire _0488_;
 wire _0489_;
 wire _0490_;
 wire _0491_;
 wire _0492_;
 wire _0493_;
 wire _0494_;
 wire _0495_;
 wire _0496_;
 wire _0497_;
 wire _0498_;
 wire _0499_;
 wire _0500_;
 wire _0501_;
 wire _0502_;
 wire _0503_;
 wire _0504_;
 wire _0505_;
 wire _0506_;
 wire _0507_;
 wire _0508_;
 wire _0509_;
 wire _0510_;
 wire _0511_;
 wire _0512_;
 wire _0513_;
 wire _0514_;
 wire _0515_;
 wire _0516_;
 wire _0517_;
 wire _0518_;
 wire _0519_;
 wire _0520_;
 wire _0521_;
 wire _0522_;
 wire _0523_;
 wire _0524_;
 wire _0525_;
 wire _0526_;
 wire _0527_;
 wire _0528_;
 wire _0529_;
 wire _0530_;
 wire _0531_;
 wire _0532_;
 wire _0533_;
 wire _0534_;
 wire _0535_;
 wire _0536_;
 wire _0537_;
 wire _0538_;
 wire _0539_;
 wire _0540_;
 wire _0541_;
 wire _0542_;
 wire _0543_;
 wire _0544_;
 wire _0545_;
 wire _0546_;
 wire _0547_;
 wire _0548_;
 wire _0549_;
 wire _0550_;
 wire _0551_;
 wire _0552_;
 wire _0553_;
 wire _0554_;
 wire _0555_;
 wire _0556_;
 wire _0557_;
 wire _0558_;
 wire _0559_;
 wire _0560_;
 wire _0561_;
 wire _0562_;
 wire _0563_;
 wire _0564_;
 wire _0565_;
 wire _0566_;
 wire _0567_;
 wire _0568_;
 wire _0569_;
 wire _0570_;
 wire _0571_;
 wire _0572_;
 wire _0573_;
 wire _0574_;
 wire _0575_;
 wire _0576_;
 wire _0577_;
 wire _0578_;
 wire _0579_;
 wire _0580_;
 wire _0581_;
 wire _0582_;
 wire _0583_;
 wire _0584_;
 wire _0585_;
 wire _0586_;
 wire _0587_;
 wire _0588_;
 wire _0589_;
 wire _0590_;
 wire _0591_;
 wire _0592_;
 wire _0593_;
 wire _0594_;
 wire _0595_;
 wire _0596_;
 wire _0597_;
 wire _0598_;
 wire _0599_;
 wire _0600_;
 wire _0601_;
 wire _0602_;
 wire _0603_;
 wire _0604_;
 wire _0605_;
 wire _0606_;
 wire _0607_;
 wire _0608_;
 wire _0609_;
 wire _0610_;
 wire _0611_;
 wire _0612_;
 wire _0613_;
 wire _0614_;
 wire _0615_;
 wire _0616_;
 wire _0617_;
 wire _0618_;
 wire _0619_;
 wire _0620_;
 wire _0621_;
 wire _0622_;
 wire _0623_;
 wire _0624_;
 wire _0625_;
 wire _0626_;
 wire _0627_;
 wire _0628_;
 wire _0629_;
 wire _0630_;
 wire _0631_;
 wire _0632_;
 wire _0633_;
 wire _0634_;
 wire _0635_;
 wire _0636_;
 wire _0637_;
 wire _0638_;
 wire _0639_;
 wire _0640_;
 wire _0641_;
 wire _0642_;
 wire _0643_;
 wire _0644_;
 wire _0645_;
 wire _0646_;
 wire _0647_;
 wire _0648_;
 wire _0649_;
 wire _0650_;
 wire _0651_;
 wire _0652_;
 wire _0653_;
 wire _0654_;
 wire _0655_;
 wire _0656_;
 wire _0657_;
 wire _0658_;
 wire _0659_;
 wire _0660_;
 wire _0661_;
 wire _0662_;
 wire _0663_;
 wire _0664_;
 wire _0665_;
 wire _0666_;
 wire _0667_;
 wire _0668_;
 wire _0669_;
 wire _0670_;
 wire _0671_;
 wire _0672_;
 wire _0673_;
 wire _0674_;
 wire _0675_;
 wire _0676_;
 wire _0677_;
 wire _0678_;
 wire _0679_;
 wire _0680_;
 wire _0681_;
 wire _0682_;
 wire _0683_;
 wire _0684_;
 wire _0685_;
 wire _0686_;
 wire _0687_;
 wire _0688_;
 wire _0689_;
 wire _0690_;
 wire _0691_;
 wire _0692_;
 wire _0693_;
 wire _0694_;
 wire _0695_;
 wire _0696_;
 wire _0697_;
 wire _0698_;
 wire _0699_;
 wire _0700_;
 wire _0701_;
 wire _0702_;
 wire _0703_;
 wire _0704_;
 wire _0705_;
 wire _0706_;
 wire _0707_;
 wire _0708_;
 wire _0709_;
 wire _0710_;
 wire _0711_;
 wire _0712_;
 wire _0713_;
 wire _0714_;
 wire _0715_;
 wire _0716_;
 wire _0717_;
 wire _0718_;
 wire _0719_;
 wire _0720_;
 wire _0721_;
 wire _0722_;
 wire _0723_;
 wire _0724_;
 wire _0725_;
 wire _0726_;
 wire _0727_;
 wire _0728_;
 wire _0729_;
 wire _0730_;
 wire _0731_;
 wire _0732_;
 wire _0733_;
 wire _0734_;
 wire _0735_;
 wire _0736_;
 wire _0737_;
 wire _0738_;
 wire _0739_;
 wire _0740_;
 wire _0741_;
 wire _0742_;
 wire _0743_;
 wire _0744_;
 wire _0745_;
 wire _0746_;
 wire _0747_;
 wire _0748_;
 wire _0749_;
 wire _0750_;
 wire _0751_;
 wire _0752_;
 wire _0753_;
 wire _0754_;
 wire _0755_;
 wire _0756_;
 wire _0757_;
 wire _0758_;
 wire _0759_;
 wire _0760_;
 wire _0761_;
 wire _0762_;
 wire _0763_;
 wire _0764_;
 wire _0765_;
 wire _0766_;
 wire _0767_;
 wire _0768_;
 wire _0769_;
 wire _0770_;
 wire _0771_;
 wire _0772_;
 wire _0773_;
 wire _0774_;
 wire _0775_;
 wire _0776_;
 wire _0777_;
 wire _0778_;
 wire _0779_;
 wire _0780_;
 wire _0781_;
 wire _0782_;
 wire _0783_;
 wire _0784_;
 wire _0785_;
 wire _0786_;
 wire _0787_;
 wire _0788_;
 wire _0789_;
 wire _0790_;
 wire _0791_;
 wire _0792_;
 wire _0793_;
 wire _0794_;
 wire _0795_;
 wire _0796_;
 wire _0797_;
 wire _0798_;
 wire _0799_;
 wire _0800_;
 wire _0801_;
 wire _0802_;
 wire _0803_;
 wire _0804_;
 wire _0805_;
 wire _0806_;
 wire _0807_;
 wire _0808_;
 wire _0809_;
 wire _0810_;
 wire _0811_;
 wire _0812_;
 wire _0813_;
 wire _0814_;
 wire _0815_;
 wire _0816_;
 wire _0817_;
 wire _0818_;
 wire _0819_;
 wire _0820_;
 wire _0821_;
 wire _0822_;
 wire _0823_;
 wire _0824_;
 wire _0825_;
 wire _0826_;
 wire _0827_;
 wire _0828_;
 wire _0829_;
 wire _0830_;
 wire _0831_;
 wire _0832_;
 wire _0833_;
 wire _0834_;
 wire _0835_;
 wire _0836_;
 wire _0837_;
 wire _0838_;
 wire _0839_;
 wire _0840_;
 wire _0841_;
 wire _0842_;
 wire _0843_;
 wire _0844_;
 wire _0845_;
 wire _0846_;
 wire _0847_;
 wire _0848_;
 wire _0849_;
 wire _0850_;
 wire _0851_;
 wire _0852_;
 wire _0853_;
 wire _0854_;
 wire _0855_;
 wire _0856_;
 wire _0857_;
 wire _0858_;
 wire _0859_;
 wire _0860_;
 wire _0861_;
 wire _0862_;
 wire _0863_;
 wire _0864_;
 wire _0865_;
 wire _0866_;
 wire _0867_;
 wire _0868_;
 wire _0869_;
 wire _0870_;
 wire _0871_;
 wire _0872_;
 wire _0873_;
 wire _0874_;
 wire _0875_;
 wire _0876_;
 wire _0877_;
 wire _0878_;
 wire _0879_;
 wire _0880_;
 wire _0881_;
 wire _0882_;
 wire _0883_;
 wire _0884_;
 wire _0885_;
 wire _0886_;
 wire _0887_;
 wire _0888_;
 wire _0889_;
 wire _0890_;
 wire _0891_;
 wire _0892_;
 wire _0893_;
 wire _0894_;
 wire _0895_;
 wire _0896_;
 wire _0897_;
 wire _0898_;
 wire _0899_;
 wire _0900_;
 wire _0901_;
 wire _0902_;
 wire _0903_;
 wire _0904_;
 wire _0905_;
 wire _0906_;
 wire _0907_;
 wire _0908_;
 wire _0909_;
 wire _0910_;
 wire _0911_;
 wire _0912_;
 wire _0913_;
 wire _0914_;
 wire _0915_;
 wire _0916_;
 wire _0917_;
 wire _0918_;
 wire _0919_;
 wire _0920_;
 wire _0921_;
 wire _0922_;
 wire _0923_;
 wire _0924_;
 wire _0925_;
 wire _0926_;
 wire _0927_;
 wire _0928_;
 wire _0929_;
 wire _0930_;
 wire _0931_;
 wire _0932_;
 wire _0933_;
 wire _0934_;
 wire _0935_;
 wire _0936_;
 wire _0937_;
 wire _0938_;
 wire _0939_;
 wire _0940_;
 wire _0941_;
 wire _0942_;
 wire _0943_;
 wire _0944_;
 wire _0945_;
 wire _0946_;
 wire _0947_;
 wire _0948_;
 wire _0949_;
 wire _0950_;
 wire _0951_;
 wire _0952_;
 wire _0953_;
 wire _0954_;
 wire _0955_;
 wire _0956_;
 wire _0957_;
 wire _0958_;
 wire _0959_;
 wire _0960_;
 wire _0961_;
 wire _0962_;
 wire _0963_;
 wire _0964_;
 wire _0965_;
 wire _0966_;
 wire _0967_;
 wire _0968_;
 wire _0969_;
 wire _0970_;
 wire _0971_;
 wire _0972_;
 wire _0973_;
 wire _0974_;
 wire _0975_;
 wire _0976_;
 wire _0977_;
 wire _0978_;
 wire _0979_;
 wire _0980_;
 wire _0981_;
 wire _0982_;
 wire _0983_;
 wire _0984_;
 wire _0985_;
 wire _0986_;
 wire _0987_;
 wire _0988_;
 wire _0989_;
 wire _0990_;
 wire _0991_;
 wire _0992_;
 wire _0993_;
 wire _0994_;
 wire _0995_;
 wire _0996_;
 wire _0997_;
 wire _0998_;
 wire _0999_;
 wire _1000_;
 wire _1001_;
 wire _1002_;
 wire _1003_;
 wire _1004_;
 wire _1005_;
 wire _1006_;
 wire _1007_;
 wire _1008_;
 wire _1009_;
 wire _1010_;
 wire _1011_;
 wire _1012_;
 wire _1013_;
 wire _1014_;
 wire _1015_;
 wire _1016_;
 wire _1017_;
 wire _1018_;
 wire _1019_;
 wire _1020_;
 wire _1021_;
 wire _1022_;
 wire _1023_;
 wire _1024_;
 wire _1025_;
 wire _1026_;
 wire _1027_;
 wire _1028_;
 wire _1029_;
 wire _1030_;
 wire _1031_;
 wire _1032_;
 wire _1033_;
 wire _1034_;
 wire _1035_;
 wire _1036_;
 wire _1037_;
 wire _1038_;
 wire _1039_;
 wire _1040_;
 wire _1041_;
 wire _1042_;
 wire _1043_;
 wire _1044_;
 wire _1045_;
 wire _1046_;
 wire _1047_;
 wire _1048_;
 wire _1049_;
 wire _1050_;
 wire _1051_;
 wire _1052_;
 wire _1053_;
 wire _1054_;
 wire _1055_;
 wire _1056_;
 wire _1057_;
 wire _1058_;
 wire _1059_;
 wire _1060_;
 wire _1061_;
 wire _1062_;
 wire _1063_;
 wire _1064_;
 wire _1065_;
 wire _1066_;
 wire _1067_;
 wire _1068_;
 wire _1069_;
 wire _1070_;
 wire _1071_;
 wire _1072_;
 wire _1073_;
 wire _1074_;
 wire _1075_;
 wire _1076_;
 wire _1077_;
 wire _1078_;
 wire _1079_;
 wire _1080_;
 wire _1081_;
 wire _1082_;
 wire _1083_;
 wire _1084_;
 wire _1085_;
 wire _1086_;
 wire _1087_;
 wire _1088_;
 wire _1089_;
 wire _1090_;
 wire _1091_;
 wire _1092_;
 wire _1093_;
 wire _1094_;
 wire _1095_;
 wire _1096_;
 wire _1097_;
 wire _1098_;
 wire _1099_;
 wire _1100_;
 wire _1101_;
 wire _1102_;
 wire _1103_;
 wire _1104_;
 wire _1105_;
 wire _1106_;
 wire _1107_;
 wire _1108_;
 wire _1109_;
 wire _1110_;
 wire _1111_;
 wire _1112_;
 wire _1113_;
 wire _1114_;
 wire _1115_;
 wire _1116_;
 wire _1117_;
 wire _1118_;
 wire _1119_;
 wire _1120_;
 wire _1121_;
 wire _1122_;
 wire _1123_;
 wire _1124_;
 wire _1125_;
 wire _1126_;
 wire _1127_;
 wire _1128_;
 wire _1129_;
 wire _1130_;
 wire _1131_;
 wire _1132_;
 wire _1133_;
 wire _1134_;
 wire _1135_;
 wire _1136_;
 wire _1137_;
 wire _1138_;
 wire _1139_;
 wire _1140_;
 wire _1141_;
 wire _1142_;
 wire _1143_;
 wire _1144_;
 wire _1145_;
 wire _1146_;
 wire _1147_;
 wire _1148_;
 wire _1149_;
 wire _1150_;
 wire _1151_;
 wire _1152_;
 wire _1153_;
 wire _1154_;
 wire _1155_;
 wire _1156_;
 wire _1157_;
 wire _1158_;
 wire _1159_;
 wire _1160_;
 wire _1161_;
 wire _1162_;
 wire _1163_;
 wire _1164_;
 wire _1165_;
 wire _1166_;
 wire _1167_;
 wire _1168_;
 wire _1169_;
 wire _1170_;
 wire _1171_;
 wire _1172_;
 wire _1173_;
 wire _1174_;
 wire _1175_;
 wire _1176_;
 wire _1177_;
 wire _1178_;
 wire _1179_;
 wire _1180_;
 wire _1181_;
 wire _1182_;
 wire _1183_;
 wire _1184_;
 wire _1185_;
 wire _1186_;
 wire _1187_;
 wire _1188_;
 wire _1189_;
 wire _1190_;
 wire _1191_;
 wire _1192_;
 wire _1193_;
 wire _1194_;
 wire _1195_;
 wire _1196_;
 wire _1197_;
 wire _1198_;
 wire _1199_;
 wire _1200_;
 wire _1201_;
 wire _1202_;
 wire _1203_;
 wire _1204_;
 wire _1205_;
 wire _1206_;
 wire _1207_;
 wire _1208_;
 wire _1209_;
 wire _1210_;
 wire _1211_;
 wire _1212_;
 wire _1213_;
 wire _1214_;
 wire _1215_;
 wire _1216_;
 wire _1217_;
 wire _1218_;
 wire _1219_;
 wire _1220_;
 wire _1221_;
 wire _1222_;
 wire _1223_;
 wire _1224_;
 wire _1225_;
 wire _1226_;
 wire _1227_;
 wire _1228_;
 wire _1229_;
 wire _1230_;
 wire _1231_;
 wire _1232_;
 wire _1233_;
 wire _1234_;
 wire _1235_;
 wire _1236_;
 wire _1237_;
 wire _1238_;
 wire _1239_;
 wire _1240_;
 wire _1241_;
 wire _1242_;
 wire _1243_;
 wire _1244_;
 wire _1245_;
 wire _1246_;
 wire _1247_;
 wire _1248_;
 wire _1249_;
 wire _1250_;
 wire _1251_;
 wire _1252_;
 wire _1253_;
 wire _1254_;
 wire _1255_;
 wire _1256_;
 wire _1257_;
 wire _1258_;
 wire _1259_;
 wire _1260_;
 wire _1261_;
 wire _1262_;
 wire _1263_;
 wire _1264_;
 wire _1265_;
 wire _1266_;
 wire _1267_;
 wire _1268_;
 wire _1269_;
 wire _1270_;
 wire _1271_;
 wire _1272_;
 wire _1273_;
 wire _1274_;
 wire _1275_;
 wire _1276_;
 wire _1277_;
 wire _1278_;
 wire _1279_;
 wire _1280_;
 wire _1281_;
 wire _1282_;
 wire _1283_;
 wire _1284_;
 wire _1285_;
 wire _1286_;
 wire _1287_;
 wire _1288_;
 wire _1289_;
 wire _1290_;
 wire _1291_;
 wire _1292_;
 wire _1293_;
 wire _1294_;
 wire _1295_;
 wire _1296_;
 wire _1297_;
 wire _1298_;
 wire _1299_;
 wire _1300_;
 wire _1301_;
 wire _1302_;
 wire _1303_;
 wire _1304_;
 wire _1305_;
 wire \r2_mantissa[0] ;
 wire \r2_mantissa[10] ;
 wire \r2_mantissa[11] ;
 wire \r2_mantissa[12] ;
 wire \r2_mantissa[13] ;
 wire \r2_mantissa[14] ;
 wire \r2_mantissa[1] ;
 wire \r2_mantissa[2] ;
 wire \r2_mantissa[3] ;
 wire \r2_mantissa[4] ;
 wire \r2_mantissa[5] ;
 wire \r2_mantissa[6] ;
 wire \r2_mantissa[7] ;
 wire \r2_mantissa[8] ;
 wire \r2_mantissa[9] ;
 wire r2_sign;
 wire \r3_prod_mant[0] ;
 wire \r3_prod_mant[10] ;
 wire \r3_prod_mant[11] ;
 wire \r3_prod_mant[12] ;
 wire \r3_prod_mant[13] ;
 wire \r3_prod_mant[14] ;
 wire \r3_prod_mant[1] ;
 wire \r3_prod_mant[2] ;
 wire \r3_prod_mant[3] ;
 wire \r3_prod_mant[4] ;
 wire \r3_prod_mant[5] ;
 wire \r3_prod_mant[6] ;
 wire \r3_prod_mant[7] ;
 wire \r3_prod_mant[8] ;
 wire \r3_prod_mant[9] ;
 wire r3_prod_sign;
 wire \r4_acc[0] ;
 wire \r4_acc[10] ;
 wire \r4_acc[11] ;
 wire \r4_acc[12] ;
 wire \r4_acc[13] ;
 wire \r4_acc[14] ;
 wire \r4_acc[15] ;
 wire \r4_acc[1] ;
 wire \r4_acc[2] ;
 wire \r4_acc[3] ;
 wire \r4_acc[4] ;
 wire \r4_acc[5] ;
 wire \r4_acc[6] ;
 wire \r4_acc[7] ;
 wire \r4_acc[8] ;
 wire \r4_acc[9] ;
 wire s1_sign_a;
 wire valid_s0;
 wire valid_s1;

 sky130_fd_sc_hd__inv_2 _1306_ (.A(\r2_mantissa[0] ),
    .Y(_0002_));
 sky130_fd_sc_hd__nand2_2 _1307_ (.A(\r4_acc[15] ),
    .B(\r4_acc[0] ),
    .Y(_0557_));
 sky130_fd_sc_hd__xnor2_2 _1308_ (.A(\r4_acc[1] ),
    .B(_0557_),
    .Y(acc_out[1]));
 sky130_fd_sc_hd__o21ai_2 _1309_ (.A1(\r4_acc[1] ),
    .A2(\r4_acc[0] ),
    .B1(\r4_acc[15] ),
    .Y(_0558_));
 sky130_fd_sc_hd__xnor2_2 _1310_ (.A(\r4_acc[2] ),
    .B(_0558_),
    .Y(acc_out[2]));
 sky130_fd_sc_hd__o31a_2 _1311_ (.A1(\r4_acc[2] ),
    .A2(\r4_acc[1] ),
    .A3(\r4_acc[0] ),
    .B1(\r4_acc[15] ),
    .X(_0559_));
 sky130_fd_sc_hd__xor2_2 _1312_ (.A(\r4_acc[3] ),
    .B(_0559_),
    .X(acc_out[3]));
 sky130_fd_sc_hd__or4_2 _1313_ (.A(\r4_acc[3] ),
    .B(\r4_acc[2] ),
    .C(\r4_acc[1] ),
    .D(\r4_acc[0] ),
    .X(_0560_));
 sky130_fd_sc_hd__nand2_2 _1314_ (.A(\r4_acc[15] ),
    .B(_0560_),
    .Y(_0561_));
 sky130_fd_sc_hd__xnor2_2 _1315_ (.A(\r4_acc[4] ),
    .B(_0561_),
    .Y(acc_out[4]));
 sky130_fd_sc_hd__o21ai_2 _1316_ (.A1(\r4_acc[4] ),
    .A2(_0560_),
    .B1(\r4_acc[15] ),
    .Y(_0562_));
 sky130_fd_sc_hd__xnor2_2 _1317_ (.A(\r4_acc[5] ),
    .B(_0562_),
    .Y(acc_out[5]));
 sky130_fd_sc_hd__o31a_2 _1318_ (.A1(\r4_acc[5] ),
    .A2(\r4_acc[4] ),
    .A3(_0560_),
    .B1(\r4_acc[15] ),
    .X(_0563_));
 sky130_fd_sc_hd__xor2_2 _1319_ (.A(\r4_acc[6] ),
    .B(_0563_),
    .X(acc_out[6]));
 sky130_fd_sc_hd__a21o_2 _1320_ (.A1(\r4_acc[15] ),
    .A2(\r4_acc[6] ),
    .B1(_0563_),
    .X(_0564_));
 sky130_fd_sc_hd__xor2_2 _1321_ (.A(\r4_acc[7] ),
    .B(_0564_),
    .X(acc_out[7]));
 sky130_fd_sc_hd__o21a_2 _1322_ (.A1(\r4_acc[7] ),
    .A2(_0564_),
    .B1(\r4_acc[15] ),
    .X(_0565_));
 sky130_fd_sc_hd__xor2_2 _1323_ (.A(\r4_acc[8] ),
    .B(_0565_),
    .X(acc_out[8]));
 sky130_fd_sc_hd__o21a_2 _1324_ (.A1(\r4_acc[8] ),
    .A2(_0565_),
    .B1(\r4_acc[15] ),
    .X(_0566_));
 sky130_fd_sc_hd__xor2_2 _1325_ (.A(\r4_acc[9] ),
    .B(_0566_),
    .X(acc_out[9]));
 sky130_fd_sc_hd__o21a_2 _1326_ (.A1(\r4_acc[9] ),
    .A2(_0566_),
    .B1(\r4_acc[15] ),
    .X(_0567_));
 sky130_fd_sc_hd__xor2_2 _1327_ (.A(\r4_acc[10] ),
    .B(_0567_),
    .X(acc_out[10]));
 sky130_fd_sc_hd__o21ai_2 _1328_ (.A1(\r4_acc[10] ),
    .A2(_0567_),
    .B1(\r4_acc[15] ),
    .Y(_0568_));
 sky130_fd_sc_hd__xnor2_2 _1329_ (.A(\r4_acc[11] ),
    .B(_0568_),
    .Y(acc_out[11]));
 sky130_fd_sc_hd__o31a_2 _1330_ (.A1(\r4_acc[11] ),
    .A2(\r4_acc[10] ),
    .A3(_0567_),
    .B1(\r4_acc[15] ),
    .X(_0569_));
 sky130_fd_sc_hd__xor2_2 _1331_ (.A(\r4_acc[12] ),
    .B(_0569_),
    .X(acc_out[12]));
 sky130_fd_sc_hd__o21ai_2 _1332_ (.A1(\r4_acc[12] ),
    .A2(_0569_),
    .B1(\r4_acc[15] ),
    .Y(_0570_));
 sky130_fd_sc_hd__xnor2_2 _1333_ (.A(\r4_acc[13] ),
    .B(_0570_),
    .Y(acc_out[13]));
 sky130_fd_sc_hd__o31a_2 _1334_ (.A1(\r4_acc[13] ),
    .A2(\r4_acc[12] ),
    .A3(_0569_),
    .B1(\r4_acc[15] ),
    .X(_0571_));
 sky130_fd_sc_hd__xor2_2 _1335_ (.A(\r4_acc[14] ),
    .B(_0571_),
    .X(acc_out[14]));
 sky130_fd_sc_hd__and2_2 _1336_ (.A(enable),
    .B(load_weight),
    .X(_0572_));
 sky130_fd_sc_hd__buf_1 _1337_ (.A(_0572_),
    .X(_0573_));
 sky130_fd_sc_hd__buf_1 _1338_ (.A(_0573_),
    .X(_0574_));
 sky130_fd_sc_hd__nand2_2 _1339_ (.A(enable),
    .B(load_weight),
    .Y(_0575_));
 sky130_fd_sc_hd__or2_2 _1340_ (.A(b_in[4]),
    .B(_0575_),
    .X(_0576_));
 sky130_fd_sc_hd__inv_2 _1341_ (.A(reset),
    .Y(_0577_));
 sky130_fd_sc_hd__buf_1 _1342_ (.A(_0577_),
    .X(_0578_));
 sky130_fd_sc_hd__buf_1 _1343_ (.A(_0578_),
    .X(_0579_));
 sky130_fd_sc_hd__o211a_2 _1344_ (.A1(\r2_mantissa[4] ),
    .A2(_0574_),
    .B1(_0576_),
    .C1(_0579_),
    .X(_0004_));
 sky130_fd_sc_hd__buf_1 _1345_ (.A(_0575_),
    .X(_0580_));
 sky130_fd_sc_hd__or2_2 _1346_ (.A(b_in[5]),
    .B(_0580_),
    .X(_0581_));
 sky130_fd_sc_hd__o211a_2 _1347_ (.A1(\r2_mantissa[5] ),
    .A2(_0574_),
    .B1(_0581_),
    .C1(_0579_),
    .X(_0005_));
 sky130_fd_sc_hd__buf_1 _1348_ (.A(_0575_),
    .X(_0582_));
 sky130_fd_sc_hd__or2_2 _1349_ (.A(b_in[6]),
    .B(_0582_),
    .X(_0583_));
 sky130_fd_sc_hd__buf_1 _1350_ (.A(_0578_),
    .X(_0584_));
 sky130_fd_sc_hd__o211a_2 _1351_ (.A1(\r2_mantissa[6] ),
    .A2(_0574_),
    .B1(_0583_),
    .C1(_0584_),
    .X(_0006_));
 sky130_fd_sc_hd__or2_2 _1352_ (.A(b_in[7]),
    .B(_0580_),
    .X(_0585_));
 sky130_fd_sc_hd__buf_1 _1353_ (.A(_0578_),
    .X(_0586_));
 sky130_fd_sc_hd__o211a_2 _1354_ (.A1(\r2_mantissa[7] ),
    .A2(_0574_),
    .B1(_0585_),
    .C1(_0586_),
    .X(_0007_));
 sky130_fd_sc_hd__or2_2 _1355_ (.A(b_in[8]),
    .B(_0580_),
    .X(_0587_));
 sky130_fd_sc_hd__o211a_2 _1356_ (.A1(\r2_mantissa[8] ),
    .A2(_0574_),
    .B1(_0587_),
    .C1(_0579_),
    .X(_0008_));
 sky130_fd_sc_hd__or2_2 _1357_ (.A(b_in[9]),
    .B(_0580_),
    .X(_0588_));
 sky130_fd_sc_hd__o211a_2 _1358_ (.A1(\r2_mantissa[9] ),
    .A2(_0573_),
    .B1(_0588_),
    .C1(_0579_),
    .X(_0009_));
 sky130_fd_sc_hd__or2_2 _1359_ (.A(b_in[10]),
    .B(_0582_),
    .X(_0589_));
 sky130_fd_sc_hd__o211a_2 _1360_ (.A1(\r2_mantissa[10] ),
    .A2(_0574_),
    .B1(_0589_),
    .C1(_0584_),
    .X(_0010_));
 sky130_fd_sc_hd__or2_2 _1361_ (.A(b_in[11]),
    .B(_0580_),
    .X(_0590_));
 sky130_fd_sc_hd__o211a_2 _1362_ (.A1(\r2_mantissa[11] ),
    .A2(_0573_),
    .B1(_0590_),
    .C1(_0579_),
    .X(_0011_));
 sky130_fd_sc_hd__or2_2 _1363_ (.A(b_in[12]),
    .B(_0580_),
    .X(_0591_));
 sky130_fd_sc_hd__o211a_2 _1364_ (.A1(\r2_mantissa[12] ),
    .A2(_0573_),
    .B1(_0591_),
    .C1(_0584_),
    .X(_0012_));
 sky130_fd_sc_hd__or2_2 _1365_ (.A(b_in[13]),
    .B(_0580_),
    .X(_0592_));
 sky130_fd_sc_hd__o211a_2 _1366_ (.A1(\r2_mantissa[13] ),
    .A2(_0573_),
    .B1(_0592_),
    .C1(_0586_),
    .X(_0013_));
 sky130_fd_sc_hd__or2_2 _1367_ (.A(b_in[14]),
    .B(_0580_),
    .X(_0593_));
 sky130_fd_sc_hd__o211a_2 _1368_ (.A1(\r2_mantissa[14] ),
    .A2(_0574_),
    .B1(_0593_),
    .C1(_0584_),
    .X(_0014_));
 sky130_fd_sc_hd__inv_2 _1369_ (.A(enable),
    .Y(_0594_));
 sky130_fd_sc_hd__nor2_2 _1370_ (.A(_0594_),
    .B(clear_acc),
    .Y(_0595_));
 sky130_fd_sc_hd__buf_1 _1371_ (.A(_0595_),
    .X(_0596_));
 sky130_fd_sc_hd__inv_2 _1372_ (.A(valid_s0),
    .Y(_0597_));
 sky130_fd_sc_hd__o2bb2a_2 _1373_ (.A1_N(compute_enable),
    .A2_N(_0596_),
    .B1(enable),
    .B2(_0597_),
    .X(_0598_));
 sky130_fd_sc_hd__nor2_2 _1374_ (.A(reset),
    .B(_0598_),
    .Y(_0015_));
 sky130_fd_sc_hd__inv_2 _1375_ (.A(\r3_prod_mant[0] ),
    .Y(_0599_));
 sky130_fd_sc_hd__inv_6 _1376_ (.A(\r2_mantissa[1] ),
    .Y(_0600_));
 sky130_fd_sc_hd__a22o_2 _1377_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[10]),
    .B1(a_out[9]),
    .B2(_0003_),
    .X(_0601_));
 sky130_fd_sc_hd__xnor2_2 _1378_ (.A(_0600_),
    .B(_0601_),
    .Y(_0602_));
 sky130_fd_sc_hd__a21o_4 _1379_ (.A1(\r2_mantissa[2] ),
    .A2(\r2_mantissa[1] ),
    .B1(\r2_mantissa[3] ),
    .X(_0603_));
 sky130_fd_sc_hd__o21ai_2 _1380_ (.A1(\r2_mantissa[2] ),
    .A2(\r2_mantissa[1] ),
    .B1(\r2_mantissa[3] ),
    .Y(_0604_));
 sky130_fd_sc_hd__xor2_2 _1381_ (.A(\r2_mantissa[2] ),
    .B(\r2_mantissa[1] ),
    .X(_0605_));
 sky130_fd_sc_hd__buf_2 _1382_ (.A(_0605_),
    .X(_0606_));
 sky130_fd_sc_hd__a32o_2 _1383_ (.A1(a_out[7]),
    .A2(_0603_),
    .A3(_0604_),
    .B1(_0606_),
    .B2(a_out[8]),
    .X(_0607_));
 sky130_fd_sc_hd__xor2_2 _1384_ (.A(\r2_mantissa[3] ),
    .B(_0607_),
    .X(_0608_));
 sky130_fd_sc_hd__xor2_2 _1385_ (.A(_0602_),
    .B(_0608_),
    .X(_0609_));
 sky130_fd_sc_hd__xor2_2 _1386_ (.A(\r2_mantissa[3] ),
    .B(\r2_mantissa[4] ),
    .X(_0610_));
 sky130_fd_sc_hd__buf_1 _1387_ (.A(_0610_),
    .X(_0611_));
 sky130_fd_sc_hd__a21o_2 _1388_ (.A1(\r2_mantissa[3] ),
    .A2(\r2_mantissa[4] ),
    .B1(\r2_mantissa[5] ),
    .X(_0612_));
 sky130_fd_sc_hd__o21ai_2 _1389_ (.A1(\r2_mantissa[3] ),
    .A2(\r2_mantissa[4] ),
    .B1(\r2_mantissa[5] ),
    .Y(_0613_));
 sky130_fd_sc_hd__and2_4 _1390_ (.A(_0612_),
    .B(_0613_),
    .X(_0614_));
 sky130_fd_sc_hd__buf_2 _1391_ (.A(_0614_),
    .X(_0615_));
 sky130_fd_sc_hd__a22o_2 _1392_ (.A1(a_out[6]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[5]),
    .X(_0616_));
 sky130_fd_sc_hd__xor2_2 _1393_ (.A(\r2_mantissa[5] ),
    .B(_0616_),
    .X(_0617_));
 sky130_fd_sc_hd__and2_2 _1394_ (.A(_0602_),
    .B(_0608_),
    .X(_0618_));
 sky130_fd_sc_hd__a21oi_2 _1395_ (.A1(_0609_),
    .A2(_0617_),
    .B1(_0618_),
    .Y(_0619_));
 sky130_fd_sc_hd__a22o_2 _1396_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[11]),
    .B1(a_out[10]),
    .B2(_0003_),
    .X(_0620_));
 sky130_fd_sc_hd__xnor2_2 _1397_ (.A(_0600_),
    .B(_0620_),
    .Y(_0621_));
 sky130_fd_sc_hd__buf_6 _1398_ (.A(_0603_),
    .X(_0622_));
 sky130_fd_sc_hd__buf_2 _1399_ (.A(_0604_),
    .X(_0623_));
 sky130_fd_sc_hd__a32o_2 _1400_ (.A1(a_out[8]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0606_),
    .B2(a_out[9]),
    .X(_0624_));
 sky130_fd_sc_hd__xor2_2 _1401_ (.A(\r2_mantissa[3] ),
    .B(_0624_),
    .X(_0625_));
 sky130_fd_sc_hd__xor2_2 _1402_ (.A(_0621_),
    .B(_0625_),
    .X(_0626_));
 sky130_fd_sc_hd__a22o_2 _1403_ (.A1(a_out[7]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[6]),
    .X(_0627_));
 sky130_fd_sc_hd__xor2_2 _1404_ (.A(\r2_mantissa[5] ),
    .B(_0627_),
    .X(_0628_));
 sky130_fd_sc_hd__xnor2_2 _1405_ (.A(_0626_),
    .B(_0628_),
    .Y(_0629_));
 sky130_fd_sc_hd__xor2_2 _1406_ (.A(_0619_),
    .B(_0629_),
    .X(_0630_));
 sky130_fd_sc_hd__xor2_2 _1407_ (.A(\r2_mantissa[6] ),
    .B(\r2_mantissa[5] ),
    .X(_0631_));
 sky130_fd_sc_hd__buf_1 _1408_ (.A(_0631_),
    .X(_0632_));
 sky130_fd_sc_hd__a21o_2 _1409_ (.A1(\r2_mantissa[6] ),
    .A2(\r2_mantissa[5] ),
    .B1(\r2_mantissa[7] ),
    .X(_0633_));
 sky130_fd_sc_hd__o21ai_2 _1410_ (.A1(\r2_mantissa[6] ),
    .A2(\r2_mantissa[5] ),
    .B1(\r2_mantissa[7] ),
    .Y(_0634_));
 sky130_fd_sc_hd__and2_2 _1411_ (.A(_0633_),
    .B(_0634_),
    .X(_0635_));
 sky130_fd_sc_hd__a22o_2 _1412_ (.A1(a_out[5]),
    .A2(_0632_),
    .B1(_0635_),
    .B2(a_out[4]),
    .X(_0636_));
 sky130_fd_sc_hd__xor2_2 _1413_ (.A(\r2_mantissa[7] ),
    .B(_0636_),
    .X(_0637_));
 sky130_fd_sc_hd__inv_2 _1414_ (.A(\r2_mantissa[9] ),
    .Y(_0638_));
 sky130_fd_sc_hd__buf_2 _1415_ (.A(_0638_),
    .X(_0639_));
 sky130_fd_sc_hd__xor2_2 _1416_ (.A(\r2_mantissa[8] ),
    .B(\r2_mantissa[7] ),
    .X(_0640_));
 sky130_fd_sc_hd__buf_1 _1417_ (.A(_0640_),
    .X(_0641_));
 sky130_fd_sc_hd__a21o_2 _1418_ (.A1(\r2_mantissa[8] ),
    .A2(\r2_mantissa[7] ),
    .B1(\r2_mantissa[9] ),
    .X(_0642_));
 sky130_fd_sc_hd__o21ai_2 _1419_ (.A1(\r2_mantissa[8] ),
    .A2(\r2_mantissa[7] ),
    .B1(\r2_mantissa[9] ),
    .Y(_0643_));
 sky130_fd_sc_hd__and2_2 _1420_ (.A(_0642_),
    .B(_0643_),
    .X(_0644_));
 sky130_fd_sc_hd__a22o_2 _1421_ (.A1(a_out[3]),
    .A2(_0641_),
    .B1(_0644_),
    .B2(a_out[2]),
    .X(_0645_));
 sky130_fd_sc_hd__xnor2_2 _1422_ (.A(_0639_),
    .B(_0645_),
    .Y(_0646_));
 sky130_fd_sc_hd__xor2_2 _1423_ (.A(_0637_),
    .B(_0646_),
    .X(_0647_));
 sky130_fd_sc_hd__inv_2 _1424_ (.A(\r2_mantissa[11] ),
    .Y(_0648_));
 sky130_fd_sc_hd__buf_1 _1425_ (.A(_0648_),
    .X(_0649_));
 sky130_fd_sc_hd__xor2_2 _1426_ (.A(\r2_mantissa[10] ),
    .B(\r2_mantissa[9] ),
    .X(_0650_));
 sky130_fd_sc_hd__buf_1 _1427_ (.A(_0650_),
    .X(_0651_));
 sky130_fd_sc_hd__a21oi_2 _1428_ (.A1(\r2_mantissa[10] ),
    .A2(\r2_mantissa[9] ),
    .B1(\r2_mantissa[11] ),
    .Y(_0652_));
 sky130_fd_sc_hd__o21a_2 _1429_ (.A1(\r2_mantissa[10] ),
    .A2(\r2_mantissa[9] ),
    .B1(\r2_mantissa[11] ),
    .X(_0653_));
 sky130_fd_sc_hd__nor2_2 _1430_ (.A(_0652_),
    .B(_0653_),
    .Y(_0654_));
 sky130_fd_sc_hd__buf_1 _1431_ (.A(_0654_),
    .X(_0655_));
 sky130_fd_sc_hd__a22o_2 _1432_ (.A1(a_out[1]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[0]),
    .X(_0656_));
 sky130_fd_sc_hd__xnor2_2 _1433_ (.A(_0649_),
    .B(_0656_),
    .Y(_0657_));
 sky130_fd_sc_hd__xor2_2 _1434_ (.A(_0647_),
    .B(_0657_),
    .X(_0658_));
 sky130_fd_sc_hd__nor2_2 _1435_ (.A(_0619_),
    .B(_0629_),
    .Y(_0659_));
 sky130_fd_sc_hd__a21oi_2 _1436_ (.A1(_0630_),
    .A2(_0658_),
    .B1(_0659_),
    .Y(_0660_));
 sky130_fd_sc_hd__and2_2 _1437_ (.A(_0621_),
    .B(_0625_),
    .X(_0661_));
 sky130_fd_sc_hd__a21oi_2 _1438_ (.A1(_0626_),
    .A2(_0628_),
    .B1(_0661_),
    .Y(_0662_));
 sky130_fd_sc_hd__a22o_2 _1439_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[12]),
    .B1(a_out[11]),
    .B2(_0003_),
    .X(_0663_));
 sky130_fd_sc_hd__xnor2_2 _1440_ (.A(_0600_),
    .B(_0663_),
    .Y(_0664_));
 sky130_fd_sc_hd__a32o_2 _1441_ (.A1(a_out[9]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0606_),
    .B2(a_out[10]),
    .X(_0665_));
 sky130_fd_sc_hd__xor2_2 _1442_ (.A(\r2_mantissa[3] ),
    .B(_0665_),
    .X(_0666_));
 sky130_fd_sc_hd__xor2_2 _1443_ (.A(_0664_),
    .B(_0666_),
    .X(_0667_));
 sky130_fd_sc_hd__a22o_2 _1444_ (.A1(a_out[8]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[7]),
    .X(_0668_));
 sky130_fd_sc_hd__xor2_2 _1445_ (.A(\r2_mantissa[5] ),
    .B(_0668_),
    .X(_0669_));
 sky130_fd_sc_hd__xnor2_2 _1446_ (.A(_0667_),
    .B(_0669_),
    .Y(_0670_));
 sky130_fd_sc_hd__xor2_2 _1447_ (.A(_0662_),
    .B(_0670_),
    .X(_0671_));
 sky130_fd_sc_hd__buf_2 _1448_ (.A(_0633_),
    .X(_0672_));
 sky130_fd_sc_hd__buf_1 _1449_ (.A(_0634_),
    .X(_0673_));
 sky130_fd_sc_hd__buf_1 _1450_ (.A(_0631_),
    .X(_0674_));
 sky130_fd_sc_hd__a32o_2 _1451_ (.A1(a_out[5]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[6]),
    .X(_0675_));
 sky130_fd_sc_hd__xor2_2 _1452_ (.A(\r2_mantissa[7] ),
    .B(_0675_),
    .X(_0676_));
 sky130_fd_sc_hd__buf_2 _1453_ (.A(_0638_),
    .X(_0677_));
 sky130_fd_sc_hd__buf_1 _1454_ (.A(_0642_),
    .X(_0678_));
 sky130_fd_sc_hd__buf_1 _1455_ (.A(_0643_),
    .X(_0679_));
 sky130_fd_sc_hd__a32o_2 _1456_ (.A1(a_out[3]),
    .A2(_0678_),
    .A3(_0679_),
    .B1(_0640_),
    .B2(a_out[4]),
    .X(_0680_));
 sky130_fd_sc_hd__xnor2_2 _1457_ (.A(_0677_),
    .B(_0680_),
    .Y(_0681_));
 sky130_fd_sc_hd__and2_2 _1458_ (.A(_0676_),
    .B(_0681_),
    .X(_0682_));
 sky130_fd_sc_hd__nor2_2 _1459_ (.A(_0676_),
    .B(_0681_),
    .Y(_0683_));
 sky130_fd_sc_hd__nor2_2 _1460_ (.A(_0682_),
    .B(_0683_),
    .Y(_0684_));
 sky130_fd_sc_hd__buf_2 _1461_ (.A(_0648_),
    .X(_0685_));
 sky130_fd_sc_hd__a22o_2 _1462_ (.A1(a_out[2]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[1]),
    .X(_0686_));
 sky130_fd_sc_hd__xnor2_2 _1463_ (.A(_0685_),
    .B(_0686_),
    .Y(_0687_));
 sky130_fd_sc_hd__xor2_2 _1464_ (.A(_0684_),
    .B(_0687_),
    .X(_0688_));
 sky130_fd_sc_hd__xor2_2 _1465_ (.A(_0671_),
    .B(_0688_),
    .X(_0689_));
 sky130_fd_sc_hd__xnor2_2 _1466_ (.A(_0660_),
    .B(_0689_),
    .Y(_0690_));
 sky130_fd_sc_hd__and2_2 _1467_ (.A(\r2_mantissa[12] ),
    .B(\r2_mantissa[11] ),
    .X(_0691_));
 sky130_fd_sc_hd__nor2_2 _1468_ (.A(\r2_mantissa[12] ),
    .B(\r2_mantissa[11] ),
    .Y(_0692_));
 sky130_fd_sc_hd__nor2_2 _1469_ (.A(_0691_),
    .B(_0692_),
    .Y(_0693_));
 sky130_fd_sc_hd__buf_1 _1470_ (.A(_0693_),
    .X(_0694_));
 sky130_fd_sc_hd__and2_2 _1471_ (.A(_0637_),
    .B(_0646_),
    .X(_0695_));
 sky130_fd_sc_hd__a21o_2 _1472_ (.A1(_0647_),
    .A2(_0657_),
    .B1(_0695_),
    .X(_0696_));
 sky130_fd_sc_hd__and3_2 _1473_ (.A(a_out[0]),
    .B(_0694_),
    .C(_0696_),
    .X(_0697_));
 sky130_fd_sc_hd__nand2_2 _1474_ (.A(a_out[0]),
    .B(_0694_),
    .Y(_0698_));
 sky130_fd_sc_hd__and2b_2 _1475_ (.A_N(_0696_),
    .B(_0698_),
    .X(_0699_));
 sky130_fd_sc_hd__nor2_2 _1476_ (.A(_0697_),
    .B(_0699_),
    .Y(_0700_));
 sky130_fd_sc_hd__xnor2_2 _1477_ (.A(_0690_),
    .B(_0700_),
    .Y(_0701_));
 sky130_fd_sc_hd__a22o_2 _1478_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[9]),
    .B1(a_out[8]),
    .B2(_0003_),
    .X(_0702_));
 sky130_fd_sc_hd__xnor2_2 _1479_ (.A(_0600_),
    .B(_0702_),
    .Y(_0703_));
 sky130_fd_sc_hd__a32o_2 _1480_ (.A1(a_out[6]),
    .A2(_0603_),
    .A3(_0604_),
    .B1(_0606_),
    .B2(a_out[7]),
    .X(_0704_));
 sky130_fd_sc_hd__xor2_2 _1481_ (.A(\r2_mantissa[3] ),
    .B(_0704_),
    .X(_0705_));
 sky130_fd_sc_hd__xor2_2 _1482_ (.A(_0703_),
    .B(_0705_),
    .X(_0706_));
 sky130_fd_sc_hd__a22o_2 _1483_ (.A1(a_out[5]),
    .A2(_0610_),
    .B1(_0615_),
    .B2(a_out[4]),
    .X(_0707_));
 sky130_fd_sc_hd__xor2_2 _1484_ (.A(\r2_mantissa[5] ),
    .B(_0707_),
    .X(_0708_));
 sky130_fd_sc_hd__and2_2 _1485_ (.A(_0703_),
    .B(_0705_),
    .X(_0709_));
 sky130_fd_sc_hd__a21oi_2 _1486_ (.A1(_0706_),
    .A2(_0708_),
    .B1(_0709_),
    .Y(_0710_));
 sky130_fd_sc_hd__xnor2_2 _1487_ (.A(_0609_),
    .B(_0617_),
    .Y(_0711_));
 sky130_fd_sc_hd__xor2_2 _1488_ (.A(_0710_),
    .B(_0711_),
    .X(_0712_));
 sky130_fd_sc_hd__a22o_2 _1489_ (.A1(a_out[4]),
    .A2(_0632_),
    .B1(_0635_),
    .B2(a_out[3]),
    .X(_0713_));
 sky130_fd_sc_hd__xor2_2 _1490_ (.A(\r2_mantissa[7] ),
    .B(_0713_),
    .X(_0714_));
 sky130_fd_sc_hd__a22o_2 _1491_ (.A1(a_out[2]),
    .A2(_0641_),
    .B1(_0644_),
    .B2(a_out[1]),
    .X(_0715_));
 sky130_fd_sc_hd__xnor2_2 _1492_ (.A(_0639_),
    .B(_0715_),
    .Y(_0716_));
 sky130_fd_sc_hd__xor2_2 _1493_ (.A(_0714_),
    .B(_0716_),
    .X(_0717_));
 sky130_fd_sc_hd__nand2_2 _1494_ (.A(a_out[0]),
    .B(_0651_),
    .Y(_0718_));
 sky130_fd_sc_hd__xnor2_2 _1495_ (.A(_0685_),
    .B(_0718_),
    .Y(_0719_));
 sky130_fd_sc_hd__xnor2_2 _1496_ (.A(_0717_),
    .B(_0719_),
    .Y(_0720_));
 sky130_fd_sc_hd__nor2_2 _1497_ (.A(_0710_),
    .B(_0711_),
    .Y(_0721_));
 sky130_fd_sc_hd__a21o_2 _1498_ (.A1(_0712_),
    .A2(_0720_),
    .B1(_0721_),
    .X(_0722_));
 sky130_fd_sc_hd__xor2_2 _1499_ (.A(_0630_),
    .B(_0658_),
    .X(_0723_));
 sky130_fd_sc_hd__xnor2_2 _1500_ (.A(_0722_),
    .B(_0723_),
    .Y(_0724_));
 sky130_fd_sc_hd__nor2_2 _1501_ (.A(_0714_),
    .B(_0716_),
    .Y(_0725_));
 sky130_fd_sc_hd__nand2_2 _1502_ (.A(_0714_),
    .B(_0716_),
    .Y(_0726_));
 sky130_fd_sc_hd__o21ai_2 _1503_ (.A1(_0725_),
    .A2(_0719_),
    .B1(_0726_),
    .Y(_0727_));
 sky130_fd_sc_hd__nand2b_2 _1504_ (.A_N(_0724_),
    .B(_0727_),
    .Y(_0728_));
 sky130_fd_sc_hd__a21boi_2 _1505_ (.A1(_0722_),
    .A2(_0723_),
    .B1_N(_0728_),
    .Y(_0729_));
 sky130_fd_sc_hd__nor2_2 _1506_ (.A(_0701_),
    .B(_0729_),
    .Y(_0730_));
 sky130_fd_sc_hd__and2b_2 _1507_ (.A_N(_0660_),
    .B(_0689_),
    .X(_0731_));
 sky130_fd_sc_hd__a21oi_2 _1508_ (.A1(_0690_),
    .A2(_0700_),
    .B1(_0731_),
    .Y(_0732_));
 sky130_fd_sc_hd__nor2_2 _1509_ (.A(_0662_),
    .B(_0670_),
    .Y(_0733_));
 sky130_fd_sc_hd__a21oi_2 _1510_ (.A1(_0671_),
    .A2(_0688_),
    .B1(_0733_),
    .Y(_0734_));
 sky130_fd_sc_hd__and2_2 _1511_ (.A(_0664_),
    .B(_0666_),
    .X(_0735_));
 sky130_fd_sc_hd__a21oi_2 _1512_ (.A1(_0667_),
    .A2(_0669_),
    .B1(_0735_),
    .Y(_0736_));
 sky130_fd_sc_hd__a22o_2 _1513_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[13]),
    .B1(a_out[12]),
    .B2(_0003_),
    .X(_0737_));
 sky130_fd_sc_hd__xnor2_2 _1514_ (.A(_0600_),
    .B(_0737_),
    .Y(_0738_));
 sky130_fd_sc_hd__a32o_2 _1515_ (.A1(a_out[10]),
    .A2(_0603_),
    .A3(_0604_),
    .B1(_0606_),
    .B2(a_out[11]),
    .X(_0739_));
 sky130_fd_sc_hd__xor2_2 _1516_ (.A(\r2_mantissa[3] ),
    .B(_0739_),
    .X(_0740_));
 sky130_fd_sc_hd__xor2_2 _1517_ (.A(_0738_),
    .B(_0740_),
    .X(_0741_));
 sky130_fd_sc_hd__a22o_2 _1518_ (.A1(a_out[9]),
    .A2(_0610_),
    .B1(_0614_),
    .B2(a_out[8]),
    .X(_0742_));
 sky130_fd_sc_hd__xor2_2 _1519_ (.A(\r2_mantissa[5] ),
    .B(_0742_),
    .X(_0743_));
 sky130_fd_sc_hd__xnor2_2 _1520_ (.A(_0741_),
    .B(_0743_),
    .Y(_0744_));
 sky130_fd_sc_hd__xor2_2 _1521_ (.A(_0736_),
    .B(_0744_),
    .X(_0745_));
 sky130_fd_sc_hd__a22o_2 _1522_ (.A1(a_out[7]),
    .A2(_0674_),
    .B1(_0635_),
    .B2(a_out[6]),
    .X(_0746_));
 sky130_fd_sc_hd__xor2_2 _1523_ (.A(\r2_mantissa[7] ),
    .B(_0746_),
    .X(_0747_));
 sky130_fd_sc_hd__a22o_2 _1524_ (.A1(a_out[5]),
    .A2(_0641_),
    .B1(_0644_),
    .B2(a_out[4]),
    .X(_0748_));
 sky130_fd_sc_hd__xnor2_2 _1525_ (.A(_0639_),
    .B(_0748_),
    .Y(_0749_));
 sky130_fd_sc_hd__xor2_2 _1526_ (.A(_0747_),
    .B(_0749_),
    .X(_0750_));
 sky130_fd_sc_hd__a22o_2 _1527_ (.A1(a_out[3]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[2]),
    .X(_0751_));
 sky130_fd_sc_hd__xnor2_2 _1528_ (.A(_0685_),
    .B(_0751_),
    .Y(_0752_));
 sky130_fd_sc_hd__xor2_2 _1529_ (.A(_0750_),
    .B(_0752_),
    .X(_0753_));
 sky130_fd_sc_hd__xnor2_2 _1530_ (.A(_0745_),
    .B(_0753_),
    .Y(_0754_));
 sky130_fd_sc_hd__xor2_2 _1531_ (.A(_0734_),
    .B(_0754_),
    .X(_0755_));
 sky130_fd_sc_hd__nand2_2 _1532_ (.A(\r2_mantissa[13] ),
    .B(_0698_),
    .Y(_0756_));
 sky130_fd_sc_hd__a21o_2 _1533_ (.A1(_0684_),
    .A2(_0687_),
    .B1(_0682_),
    .X(_0757_));
 sky130_fd_sc_hd__inv_2 _1534_ (.A(\r2_mantissa[13] ),
    .Y(_0758_));
 sky130_fd_sc_hd__buf_2 _1535_ (.A(_0758_),
    .X(_0759_));
 sky130_fd_sc_hd__buf_2 _1536_ (.A(_0759_),
    .X(_0760_));
 sky130_fd_sc_hd__and3b_2 _1537_ (.A_N(\r2_mantissa[13] ),
    .B(\r2_mantissa[12] ),
    .C(\r2_mantissa[11] ),
    .X(_0761_));
 sky130_fd_sc_hd__a21o_2 _1538_ (.A1(\r2_mantissa[13] ),
    .A2(_0692_),
    .B1(_0761_),
    .X(_0762_));
 sky130_fd_sc_hd__buf_1 _1539_ (.A(_0762_),
    .X(_0763_));
 sky130_fd_sc_hd__a22o_2 _1540_ (.A1(a_out[1]),
    .A2(_0694_),
    .B1(_0763_),
    .B2(a_out[0]),
    .X(_0764_));
 sky130_fd_sc_hd__xnor2_2 _1541_ (.A(_0760_),
    .B(_0764_),
    .Y(_0765_));
 sky130_fd_sc_hd__xor2_2 _1542_ (.A(_0757_),
    .B(_0765_),
    .X(_0766_));
 sky130_fd_sc_hd__xnor2_2 _1543_ (.A(_0756_),
    .B(_0766_),
    .Y(_0767_));
 sky130_fd_sc_hd__xor2_2 _1544_ (.A(_0755_),
    .B(_0767_),
    .X(_0768_));
 sky130_fd_sc_hd__xnor2_2 _1545_ (.A(_0732_),
    .B(_0768_),
    .Y(_0769_));
 sky130_fd_sc_hd__xor2_2 _1546_ (.A(_0697_),
    .B(_0769_),
    .X(_0770_));
 sky130_fd_sc_hd__and2b_2 _1547_ (.A_N(_0732_),
    .B(_0768_),
    .X(_0771_));
 sky130_fd_sc_hd__a21oi_2 _1548_ (.A1(_0697_),
    .A2(_0769_),
    .B1(_0771_),
    .Y(_0772_));
 sky130_fd_sc_hd__and2_2 _1549_ (.A(_0757_),
    .B(_0765_),
    .X(_0773_));
 sky130_fd_sc_hd__a31o_2 _1550_ (.A1(\r2_mantissa[13] ),
    .A2(_0698_),
    .A3(_0766_),
    .B1(_0773_),
    .X(_0774_));
 sky130_fd_sc_hd__and2_2 _1551_ (.A(_0747_),
    .B(_0749_),
    .X(_0775_));
 sky130_fd_sc_hd__a21o_2 _1552_ (.A1(_0750_),
    .A2(_0752_),
    .B1(_0775_),
    .X(_0776_));
 sky130_fd_sc_hd__a22o_2 _1553_ (.A1(a_out[2]),
    .A2(_0694_),
    .B1(_0763_),
    .B2(a_out[1]),
    .X(_0777_));
 sky130_fd_sc_hd__xnor2_2 _1554_ (.A(_0760_),
    .B(_0777_),
    .Y(_0778_));
 sky130_fd_sc_hd__nand3_2 _1555_ (.A(a_out[0]),
    .B(_0001_),
    .C(_0778_),
    .Y(_0779_));
 sky130_fd_sc_hd__a21o_2 _1556_ (.A1(a_out[0]),
    .A2(_0001_),
    .B1(_0778_),
    .X(_0780_));
 sky130_fd_sc_hd__nand2_2 _1557_ (.A(_0779_),
    .B(_0780_),
    .Y(_0781_));
 sky130_fd_sc_hd__xor2_2 _1558_ (.A(_0776_),
    .B(_0781_),
    .X(_0782_));
 sky130_fd_sc_hd__a32o_2 _1559_ (.A1(a_out[7]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[8]),
    .X(_0783_));
 sky130_fd_sc_hd__xor2_2 _1560_ (.A(\r2_mantissa[7] ),
    .B(_0783_),
    .X(_0784_));
 sky130_fd_sc_hd__a32o_2 _1561_ (.A1(a_out[5]),
    .A2(_0642_),
    .A3(_0643_),
    .B1(_0640_),
    .B2(a_out[6]),
    .X(_0785_));
 sky130_fd_sc_hd__xnor2_2 _1562_ (.A(_0638_),
    .B(_0785_),
    .Y(_0786_));
 sky130_fd_sc_hd__and2_2 _1563_ (.A(_0784_),
    .B(_0786_),
    .X(_0787_));
 sky130_fd_sc_hd__nor2_2 _1564_ (.A(_0784_),
    .B(_0786_),
    .Y(_0788_));
 sky130_fd_sc_hd__nor2_2 _1565_ (.A(_0787_),
    .B(_0788_),
    .Y(_0789_));
 sky130_fd_sc_hd__a22o_2 _1566_ (.A1(a_out[4]),
    .A2(_0650_),
    .B1(_0654_),
    .B2(a_out[3]),
    .X(_0790_));
 sky130_fd_sc_hd__xnor2_2 _1567_ (.A(_0648_),
    .B(_0790_),
    .Y(_0791_));
 sky130_fd_sc_hd__xor2_2 _1568_ (.A(_0789_),
    .B(_0791_),
    .X(_0792_));
 sky130_fd_sc_hd__a22o_2 _1569_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[14]),
    .B1(a_out[13]),
    .B2(_0003_),
    .X(_0793_));
 sky130_fd_sc_hd__xnor2_2 _1570_ (.A(_0600_),
    .B(_0793_),
    .Y(_0794_));
 sky130_fd_sc_hd__a32o_2 _1571_ (.A1(a_out[11]),
    .A2(_0603_),
    .A3(_0604_),
    .B1(_0606_),
    .B2(a_out[12]),
    .X(_0795_));
 sky130_fd_sc_hd__xor2_2 _1572_ (.A(\r2_mantissa[3] ),
    .B(_0795_),
    .X(_0796_));
 sky130_fd_sc_hd__xor2_2 _1573_ (.A(_0794_),
    .B(_0796_),
    .X(_0797_));
 sky130_fd_sc_hd__a22o_2 _1574_ (.A1(a_out[10]),
    .A2(_0610_),
    .B1(_0614_),
    .B2(a_out[9]),
    .X(_0798_));
 sky130_fd_sc_hd__xor2_2 _1575_ (.A(\r2_mantissa[5] ),
    .B(_0798_),
    .X(_0799_));
 sky130_fd_sc_hd__xor2_2 _1576_ (.A(_0797_),
    .B(_0799_),
    .X(_0800_));
 sky130_fd_sc_hd__and2_2 _1577_ (.A(_0738_),
    .B(_0740_),
    .X(_0801_));
 sky130_fd_sc_hd__a21oi_2 _1578_ (.A1(_0741_),
    .A2(_0743_),
    .B1(_0801_),
    .Y(_0802_));
 sky130_fd_sc_hd__xnor2_2 _1579_ (.A(_0800_),
    .B(_0802_),
    .Y(_0803_));
 sky130_fd_sc_hd__xnor2_2 _1580_ (.A(_0792_),
    .B(_0803_),
    .Y(_0804_));
 sky130_fd_sc_hd__nor2_2 _1581_ (.A(_0736_),
    .B(_0744_),
    .Y(_0805_));
 sky130_fd_sc_hd__a21oi_2 _1582_ (.A1(_0745_),
    .A2(_0753_),
    .B1(_0805_),
    .Y(_0806_));
 sky130_fd_sc_hd__xnor2_2 _1583_ (.A(_0804_),
    .B(_0806_),
    .Y(_0807_));
 sky130_fd_sc_hd__xor2_2 _1584_ (.A(_0782_),
    .B(_0807_),
    .X(_0808_));
 sky130_fd_sc_hd__nor2_2 _1585_ (.A(_0734_),
    .B(_0754_),
    .Y(_0809_));
 sky130_fd_sc_hd__a21o_2 _1586_ (.A1(_0755_),
    .A2(_0767_),
    .B1(_0809_),
    .X(_0810_));
 sky130_fd_sc_hd__xor2_2 _1587_ (.A(_0808_),
    .B(_0810_),
    .X(_0811_));
 sky130_fd_sc_hd__xnor2_2 _1588_ (.A(_0774_),
    .B(_0811_),
    .Y(_0812_));
 sky130_fd_sc_hd__or2_2 _1589_ (.A(_0772_),
    .B(_0812_),
    .X(_0813_));
 sky130_fd_sc_hd__nand2_2 _1590_ (.A(_0772_),
    .B(_0812_),
    .Y(_0814_));
 sky130_fd_sc_hd__o211a_2 _1591_ (.A1(_0730_),
    .A2(_0770_),
    .B1(_0813_),
    .C1(_0814_),
    .X(_0815_));
 sky130_fd_sc_hd__a22o_2 _1592_ (.A1(a_out[3]),
    .A2(_0632_),
    .B1(_0635_),
    .B2(a_out[2]),
    .X(_0816_));
 sky130_fd_sc_hd__xor2_2 _1593_ (.A(\r2_mantissa[7] ),
    .B(_0816_),
    .X(_0817_));
 sky130_fd_sc_hd__a22o_2 _1594_ (.A1(a_out[1]),
    .A2(_0641_),
    .B1(_0644_),
    .B2(a_out[0]),
    .X(_0818_));
 sky130_fd_sc_hd__xnor2_2 _1595_ (.A(_0639_),
    .B(_0818_),
    .Y(_0819_));
 sky130_fd_sc_hd__nand2_2 _1596_ (.A(_0817_),
    .B(_0819_),
    .Y(_0820_));
 sky130_fd_sc_hd__nor2_2 _1597_ (.A(_0649_),
    .B(_0820_),
    .Y(_0821_));
 sky130_fd_sc_hd__and2_2 _1598_ (.A(_0649_),
    .B(_0820_),
    .X(_0822_));
 sky130_fd_sc_hd__or2_2 _1599_ (.A(_0821_),
    .B(_0822_),
    .X(_0823_));
 sky130_fd_sc_hd__a22o_2 _1600_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[8]),
    .B1(a_out[7]),
    .B2(_0003_),
    .X(_0824_));
 sky130_fd_sc_hd__xnor2_2 _1601_ (.A(_0600_),
    .B(_0824_),
    .Y(_0825_));
 sky130_fd_sc_hd__buf_1 _1602_ (.A(_0605_),
    .X(_0826_));
 sky130_fd_sc_hd__a32o_2 _1603_ (.A1(a_out[5]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0826_),
    .B2(a_out[6]),
    .X(_0827_));
 sky130_fd_sc_hd__xor2_2 _1604_ (.A(\r2_mantissa[3] ),
    .B(_0827_),
    .X(_0828_));
 sky130_fd_sc_hd__xor2_2 _1605_ (.A(_0825_),
    .B(_0828_),
    .X(_0829_));
 sky130_fd_sc_hd__a22o_2 _1606_ (.A1(a_out[4]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[3]),
    .X(_0830_));
 sky130_fd_sc_hd__xor2_2 _1607_ (.A(\r2_mantissa[5] ),
    .B(_0830_),
    .X(_0831_));
 sky130_fd_sc_hd__and2_2 _1608_ (.A(_0825_),
    .B(_0828_),
    .X(_0832_));
 sky130_fd_sc_hd__a21oi_2 _1609_ (.A1(_0829_),
    .A2(_0831_),
    .B1(_0832_),
    .Y(_0833_));
 sky130_fd_sc_hd__xnor2_2 _1610_ (.A(_0706_),
    .B(_0708_),
    .Y(_0834_));
 sky130_fd_sc_hd__nand2_2 _1611_ (.A(_0833_),
    .B(_0834_),
    .Y(_0835_));
 sky130_fd_sc_hd__or2_2 _1612_ (.A(_0817_),
    .B(_0819_),
    .X(_0836_));
 sky130_fd_sc_hd__and2_2 _1613_ (.A(_0820_),
    .B(_0836_),
    .X(_0837_));
 sky130_fd_sc_hd__nor2_2 _1614_ (.A(_0833_),
    .B(_0834_),
    .Y(_0838_));
 sky130_fd_sc_hd__a21o_2 _1615_ (.A1(_0835_),
    .A2(_0837_),
    .B1(_0838_),
    .X(_0839_));
 sky130_fd_sc_hd__xor2_2 _1616_ (.A(_0712_),
    .B(_0720_),
    .X(_0840_));
 sky130_fd_sc_hd__xnor2_2 _1617_ (.A(_0839_),
    .B(_0840_),
    .Y(_0841_));
 sky130_fd_sc_hd__nand2_2 _1618_ (.A(_0839_),
    .B(_0840_),
    .Y(_0842_));
 sky130_fd_sc_hd__o21a_2 _1619_ (.A1(_0823_),
    .A2(_0841_),
    .B1(_0842_),
    .X(_0843_));
 sky130_fd_sc_hd__xnor2_2 _1620_ (.A(_0727_),
    .B(_0724_),
    .Y(_0844_));
 sky130_fd_sc_hd__xnor2_2 _1621_ (.A(_0843_),
    .B(_0844_),
    .Y(_0845_));
 sky130_fd_sc_hd__xnor2_2 _1622_ (.A(_0821_),
    .B(_0845_),
    .Y(_0846_));
 sky130_fd_sc_hd__a22o_2 _1623_ (.A1(a_out[2]),
    .A2(_0632_),
    .B1(_0635_),
    .B2(a_out[1]),
    .X(_0847_));
 sky130_fd_sc_hd__xor2_2 _1624_ (.A(\r2_mantissa[7] ),
    .B(_0847_),
    .X(_0848_));
 sky130_fd_sc_hd__nand2_2 _1625_ (.A(a_out[0]),
    .B(_0641_),
    .Y(_0849_));
 sky130_fd_sc_hd__mux2_2 _1626_ (.A0(_0848_),
    .A1(\r2_mantissa[9] ),
    .S(_0849_),
    .X(_0850_));
 sky130_fd_sc_hd__buf_2 _1627_ (.A(_0600_),
    .X(_0851_));
 sky130_fd_sc_hd__a22o_2 _1628_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[7]),
    .B1(a_out[6]),
    .B2(_0003_),
    .X(_0852_));
 sky130_fd_sc_hd__xnor2_2 _1629_ (.A(_0851_),
    .B(_0852_),
    .Y(_0853_));
 sky130_fd_sc_hd__a32o_2 _1630_ (.A1(a_out[4]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0826_),
    .B2(a_out[5]),
    .X(_0854_));
 sky130_fd_sc_hd__xor2_2 _1631_ (.A(\r2_mantissa[3] ),
    .B(_0854_),
    .X(_0855_));
 sky130_fd_sc_hd__xor2_2 _1632_ (.A(_0853_),
    .B(_0855_),
    .X(_0856_));
 sky130_fd_sc_hd__a22o_2 _1633_ (.A1(a_out[3]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[2]),
    .X(_0857_));
 sky130_fd_sc_hd__xor2_2 _1634_ (.A(\r2_mantissa[5] ),
    .B(_0857_),
    .X(_0858_));
 sky130_fd_sc_hd__and2_2 _1635_ (.A(_0853_),
    .B(_0855_),
    .X(_0859_));
 sky130_fd_sc_hd__a21oi_2 _1636_ (.A1(_0856_),
    .A2(_0858_),
    .B1(_0859_),
    .Y(_0860_));
 sky130_fd_sc_hd__xnor2_2 _1637_ (.A(_0829_),
    .B(_0831_),
    .Y(_0861_));
 sky130_fd_sc_hd__xor2_2 _1638_ (.A(_0860_),
    .B(_0861_),
    .X(_0862_));
 sky130_fd_sc_hd__xnor2_2 _1639_ (.A(_0849_),
    .B(_0848_),
    .Y(_0863_));
 sky130_fd_sc_hd__nor2_2 _1640_ (.A(_0860_),
    .B(_0861_),
    .Y(_0864_));
 sky130_fd_sc_hd__a21oi_2 _1641_ (.A1(_0862_),
    .A2(_0863_),
    .B1(_0864_),
    .Y(_0865_));
 sky130_fd_sc_hd__xnor2_2 _1642_ (.A(_0833_),
    .B(_0834_),
    .Y(_0866_));
 sky130_fd_sc_hd__xnor2_2 _1643_ (.A(_0866_),
    .B(_0837_),
    .Y(_0867_));
 sky130_fd_sc_hd__xnor2_2 _1644_ (.A(_0865_),
    .B(_0867_),
    .Y(_0868_));
 sky130_fd_sc_hd__xnor2_2 _1645_ (.A(_0850_),
    .B(_0868_),
    .Y(_0869_));
 sky130_fd_sc_hd__a22o_2 _1646_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[6]),
    .B1(a_out[5]),
    .B2(_0003_),
    .X(_0870_));
 sky130_fd_sc_hd__xnor2_2 _1647_ (.A(_0851_),
    .B(_0870_),
    .Y(_0871_));
 sky130_fd_sc_hd__a32o_2 _1648_ (.A1(a_out[3]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0826_),
    .B2(a_out[4]),
    .X(_0872_));
 sky130_fd_sc_hd__xor2_2 _1649_ (.A(\r2_mantissa[3] ),
    .B(_0872_),
    .X(_0873_));
 sky130_fd_sc_hd__xor2_2 _1650_ (.A(_0871_),
    .B(_0873_),
    .X(_0874_));
 sky130_fd_sc_hd__a22o_2 _1651_ (.A1(a_out[2]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[1]),
    .X(_0875_));
 sky130_fd_sc_hd__xor2_2 _1652_ (.A(\r2_mantissa[5] ),
    .B(_0875_),
    .X(_0876_));
 sky130_fd_sc_hd__and2_2 _1653_ (.A(_0871_),
    .B(_0873_),
    .X(_0877_));
 sky130_fd_sc_hd__a21oi_2 _1654_ (.A1(_0874_),
    .A2(_0876_),
    .B1(_0877_),
    .Y(_0878_));
 sky130_fd_sc_hd__xnor2_2 _1655_ (.A(_0856_),
    .B(_0858_),
    .Y(_0879_));
 sky130_fd_sc_hd__or2_2 _1656_ (.A(_0878_),
    .B(_0879_),
    .X(_0880_));
 sky130_fd_sc_hd__xor2_2 _1657_ (.A(_0878_),
    .B(_0879_),
    .X(_0881_));
 sky130_fd_sc_hd__a22o_2 _1658_ (.A1(a_out[1]),
    .A2(_0632_),
    .B1(_0635_),
    .B2(a_out[0]),
    .X(_0882_));
 sky130_fd_sc_hd__xor2_2 _1659_ (.A(\r2_mantissa[7] ),
    .B(_0882_),
    .X(_0883_));
 sky130_fd_sc_hd__nand2_2 _1660_ (.A(_0881_),
    .B(_0883_),
    .Y(_0884_));
 sky130_fd_sc_hd__xnor2_2 _1661_ (.A(_0862_),
    .B(_0863_),
    .Y(_0885_));
 sky130_fd_sc_hd__a21o_2 _1662_ (.A1(_0880_),
    .A2(_0884_),
    .B1(_0885_),
    .X(_0886_));
 sky130_fd_sc_hd__or2_2 _1663_ (.A(_0869_),
    .B(_0886_),
    .X(_0887_));
 sky130_fd_sc_hd__xor2_2 _1664_ (.A(_0823_),
    .B(_0841_),
    .X(_0888_));
 sky130_fd_sc_hd__and2b_2 _1665_ (.A_N(_0865_),
    .B(_0867_),
    .X(_0889_));
 sky130_fd_sc_hd__a21oi_2 _1666_ (.A1(_0850_),
    .A2(_0868_),
    .B1(_0889_),
    .Y(_0890_));
 sky130_fd_sc_hd__xor2_2 _1667_ (.A(_0888_),
    .B(_0890_),
    .X(_0891_));
 sky130_fd_sc_hd__or2b_2 _1668_ (.A(_0890_),
    .B_N(_0888_),
    .X(_0892_));
 sky130_fd_sc_hd__o21a_2 _1669_ (.A1(_0887_),
    .A2(_0891_),
    .B1(_0892_),
    .X(_0893_));
 sky130_fd_sc_hd__nand2_2 _1670_ (.A(a_out[0]),
    .B(_0632_),
    .Y(_0894_));
 sky130_fd_sc_hd__and2_2 _1671_ (.A(\r2_mantissa[7] ),
    .B(_0894_),
    .X(_0895_));
 sky130_fd_sc_hd__a22o_2 _1672_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[5]),
    .B1(a_out[4]),
    .B2(_0003_),
    .X(_0896_));
 sky130_fd_sc_hd__xnor2_2 _1673_ (.A(_0851_),
    .B(_0896_),
    .Y(_0897_));
 sky130_fd_sc_hd__a32o_2 _1674_ (.A1(a_out[2]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0826_),
    .B2(a_out[3]),
    .X(_0898_));
 sky130_fd_sc_hd__xor2_2 _1675_ (.A(\r2_mantissa[3] ),
    .B(_0898_),
    .X(_0899_));
 sky130_fd_sc_hd__xor2_2 _1676_ (.A(_0897_),
    .B(_0899_),
    .X(_0900_));
 sky130_fd_sc_hd__a22o_2 _1677_ (.A1(a_out[1]),
    .A2(_0611_),
    .B1(_0615_),
    .B2(a_out[0]),
    .X(_0901_));
 sky130_fd_sc_hd__xor2_2 _1678_ (.A(\r2_mantissa[5] ),
    .B(_0901_),
    .X(_0902_));
 sky130_fd_sc_hd__and2_2 _1679_ (.A(_0897_),
    .B(_0899_),
    .X(_0903_));
 sky130_fd_sc_hd__a21oi_2 _1680_ (.A1(_0900_),
    .A2(_0902_),
    .B1(_0903_),
    .Y(_0904_));
 sky130_fd_sc_hd__xnor2_2 _1681_ (.A(_0874_),
    .B(_0876_),
    .Y(_0905_));
 sky130_fd_sc_hd__xor2_2 _1682_ (.A(_0904_),
    .B(_0905_),
    .X(_0906_));
 sky130_fd_sc_hd__nor2_2 _1683_ (.A(_0904_),
    .B(_0905_),
    .Y(_0907_));
 sky130_fd_sc_hd__a31o_2 _1684_ (.A1(a_out[0]),
    .A2(_0632_),
    .A3(_0906_),
    .B1(_0907_),
    .X(_0908_));
 sky130_fd_sc_hd__xor2_2 _1685_ (.A(_0881_),
    .B(_0883_),
    .X(_0909_));
 sky130_fd_sc_hd__xor2_2 _1686_ (.A(_0908_),
    .B(_0909_),
    .X(_0910_));
 sky130_fd_sc_hd__nand2_2 _1687_ (.A(_0908_),
    .B(_0909_),
    .Y(_0911_));
 sky130_fd_sc_hd__a21boi_2 _1688_ (.A1(_0895_),
    .A2(_0910_),
    .B1_N(_0911_),
    .Y(_0912_));
 sky130_fd_sc_hd__nand3_2 _1689_ (.A(_0885_),
    .B(_0880_),
    .C(_0884_),
    .Y(_0913_));
 sky130_fd_sc_hd__nand2_2 _1690_ (.A(_0886_),
    .B(_0913_),
    .Y(_0914_));
 sky130_fd_sc_hd__a2111o_2 _1691_ (.A1(_0887_),
    .A2(_0891_),
    .B1(_0912_),
    .C1(_0914_),
    .D1(_0869_),
    .X(_0915_));
 sky130_fd_sc_hd__a22o_2 _1692_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[4]),
    .B1(a_out[3]),
    .B2(_0003_),
    .X(_0916_));
 sky130_fd_sc_hd__xnor2_2 _1693_ (.A(_0851_),
    .B(_0916_),
    .Y(_0917_));
 sky130_fd_sc_hd__a32o_2 _1694_ (.A1(a_out[1]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0826_),
    .B2(a_out[2]),
    .X(_0918_));
 sky130_fd_sc_hd__xor2_2 _1695_ (.A(\r2_mantissa[3] ),
    .B(_0918_),
    .X(_0919_));
 sky130_fd_sc_hd__xor2_2 _1696_ (.A(_0917_),
    .B(_0919_),
    .X(_0920_));
 sky130_fd_sc_hd__nand2_2 _1697_ (.A(a_out[0]),
    .B(_0611_),
    .Y(_0921_));
 sky130_fd_sc_hd__xnor2_2 _1698_ (.A(\r2_mantissa[5] ),
    .B(_0921_),
    .Y(_0922_));
 sky130_fd_sc_hd__xnor2_2 _1699_ (.A(_0920_),
    .B(_0922_),
    .Y(_0923_));
 sky130_fd_sc_hd__a22o_2 _1700_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[3]),
    .B1(a_out[2]),
    .B2(_0003_),
    .X(_0924_));
 sky130_fd_sc_hd__xnor2_2 _1701_ (.A(_0851_),
    .B(_0924_),
    .Y(_0925_));
 sky130_fd_sc_hd__a32o_2 _1702_ (.A1(a_out[0]),
    .A2(_0622_),
    .A3(_0623_),
    .B1(_0826_),
    .B2(a_out[1]),
    .X(_0926_));
 sky130_fd_sc_hd__xor2_2 _1703_ (.A(\r2_mantissa[3] ),
    .B(_0926_),
    .X(_0927_));
 sky130_fd_sc_hd__nand2_2 _1704_ (.A(_0925_),
    .B(_0927_),
    .Y(_0928_));
 sky130_fd_sc_hd__xor2_2 _1705_ (.A(_0923_),
    .B(_0928_),
    .X(_0929_));
 sky130_fd_sc_hd__xor2_2 _1706_ (.A(\r2_mantissa[5] ),
    .B(_0929_),
    .X(_0930_));
 sky130_fd_sc_hd__xnor2_2 _1707_ (.A(_0894_),
    .B(_0906_),
    .Y(_0931_));
 sky130_fd_sc_hd__xor2_2 _1708_ (.A(_0925_),
    .B(_0927_),
    .X(_0932_));
 sky130_fd_sc_hd__nand2_2 _1709_ (.A(a_out[0]),
    .B(_0826_),
    .Y(_0933_));
 sky130_fd_sc_hd__a22o_2 _1710_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[2]),
    .B1(a_out[1]),
    .B2(_0003_),
    .X(_0934_));
 sky130_fd_sc_hd__xnor2_2 _1711_ (.A(\r2_mantissa[1] ),
    .B(_0934_),
    .Y(_0935_));
 sky130_fd_sc_hd__nor2_2 _1712_ (.A(_0933_),
    .B(_0935_),
    .Y(_0936_));
 sky130_fd_sc_hd__a21o_2 _1713_ (.A1(\r2_mantissa[3] ),
    .A2(_0933_),
    .B1(_0936_),
    .X(_0937_));
 sky130_fd_sc_hd__and2_2 _1714_ (.A(_0932_),
    .B(_0937_),
    .X(_0938_));
 sky130_fd_sc_hd__nand2_2 _1715_ (.A(_0900_),
    .B(_0902_),
    .Y(_0939_));
 sky130_fd_sc_hd__or2_2 _1716_ (.A(_0900_),
    .B(_0902_),
    .X(_0940_));
 sky130_fd_sc_hd__nand2_2 _1717_ (.A(_0939_),
    .B(_0940_),
    .Y(_0941_));
 sky130_fd_sc_hd__and2_2 _1718_ (.A(_0917_),
    .B(_0919_),
    .X(_0942_));
 sky130_fd_sc_hd__a21o_2 _1719_ (.A1(_0920_),
    .A2(_0922_),
    .B1(_0942_),
    .X(_0943_));
 sky130_fd_sc_hd__xnor2_2 _1720_ (.A(_0941_),
    .B(_0943_),
    .Y(_0944_));
 sky130_fd_sc_hd__nor2_2 _1721_ (.A(_0923_),
    .B(_0928_),
    .Y(_0945_));
 sky130_fd_sc_hd__a21o_2 _1722_ (.A1(\r2_mantissa[5] ),
    .A2(_0929_),
    .B1(_0945_),
    .X(_0946_));
 sky130_fd_sc_hd__or2_2 _1723_ (.A(_0944_),
    .B(_0946_),
    .X(_0947_));
 sky130_fd_sc_hd__nand4_2 _1724_ (.A(_0930_),
    .B(_0931_),
    .C(_0938_),
    .D(_0947_),
    .Y(_0948_));
 sky130_fd_sc_hd__and3_2 _1725_ (.A(_0939_),
    .B(_0940_),
    .C(_0943_),
    .X(_0949_));
 sky130_fd_sc_hd__nand2_2 _1726_ (.A(_0931_),
    .B(_0949_),
    .Y(_0950_));
 sky130_fd_sc_hd__or2_2 _1727_ (.A(\r2_mantissa[0] ),
    .B(_0003_),
    .X(_0951_));
 sky130_fd_sc_hd__a221o_2 _1728_ (.A1(\r2_mantissa[0] ),
    .A2(a_out[1]),
    .B1(a_out[0]),
    .B2(_0951_),
    .C1(_0936_),
    .X(_0952_));
 sky130_fd_sc_hd__a2111o_2 _1729_ (.A1(_0933_),
    .A2(_0934_),
    .B1(_0938_),
    .C1(_0952_),
    .D1(_0851_),
    .X(_0953_));
 sky130_fd_sc_hd__o21ba_2 _1730_ (.A1(_0932_),
    .A2(_0937_),
    .B1_N(_0953_),
    .X(_0954_));
 sky130_fd_sc_hd__a22o_2 _1731_ (.A1(_0944_),
    .A2(_0946_),
    .B1(_0954_),
    .B2(_0930_),
    .X(_0955_));
 sky130_fd_sc_hd__o211ai_2 _1732_ (.A1(_0931_),
    .A2(_0949_),
    .B1(_0947_),
    .C1(_0955_),
    .Y(_0956_));
 sky130_fd_sc_hd__xnor2_2 _1733_ (.A(_0895_),
    .B(_0910_),
    .Y(_0957_));
 sky130_fd_sc_hd__a31o_2 _1734_ (.A1(_0948_),
    .A2(_0950_),
    .A3(_0956_),
    .B1(_0957_),
    .X(_0958_));
 sky130_fd_sc_hd__xnor2_2 _1735_ (.A(_0869_),
    .B(_0886_),
    .Y(_0959_));
 sky130_fd_sc_hd__xnor2_2 _1736_ (.A(_0912_),
    .B(_0914_),
    .Y(_0960_));
 sky130_fd_sc_hd__or4_4 _1737_ (.A(_0891_),
    .B(_0958_),
    .C(_0959_),
    .D(_0960_),
    .X(_0961_));
 sky130_fd_sc_hd__o211a_2 _1738_ (.A1(_0846_),
    .A2(_0893_),
    .B1(_0915_),
    .C1(_0961_),
    .X(_0962_));
 sky130_fd_sc_hd__and2b_2 _1739_ (.A_N(_0843_),
    .B(_0844_),
    .X(_0963_));
 sky130_fd_sc_hd__a21oi_2 _1740_ (.A1(_0821_),
    .A2(_0845_),
    .B1(_0963_),
    .Y(_0964_));
 sky130_fd_sc_hd__xnor2_2 _1741_ (.A(_0701_),
    .B(_0729_),
    .Y(_0965_));
 sky130_fd_sc_hd__a22o_2 _1742_ (.A1(_0964_),
    .A2(_0965_),
    .B1(_0846_),
    .B2(_0893_),
    .X(_0966_));
 sky130_fd_sc_hd__o2bb2a_2 _1743_ (.A1_N(_0730_),
    .A2_N(_0770_),
    .B1(_0964_),
    .B2(_0965_),
    .X(_0967_));
 sky130_fd_sc_hd__o21ai_4 _1744_ (.A1(_0962_),
    .A2(_0966_),
    .B1(_0967_),
    .Y(_0968_));
 sky130_fd_sc_hd__nand2_2 _1745_ (.A(_0808_),
    .B(_0810_),
    .Y(_0969_));
 sky130_fd_sc_hd__a21boi_2 _1746_ (.A1(_0774_),
    .A2(_0811_),
    .B1_N(_0969_),
    .Y(_0970_));
 sky130_fd_sc_hd__and3_2 _1747_ (.A(_0776_),
    .B(_0779_),
    .C(_0780_),
    .X(_0971_));
 sky130_fd_sc_hd__a21o_2 _1748_ (.A1(_0789_),
    .A2(_0791_),
    .B1(_0787_),
    .X(_0972_));
 sky130_fd_sc_hd__a22o_2 _1749_ (.A1(a_out[1]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[0]),
    .X(_0973_));
 sky130_fd_sc_hd__buf_1 _1750_ (.A(_0693_),
    .X(_0974_));
 sky130_fd_sc_hd__a22o_2 _1751_ (.A1(a_out[3]),
    .A2(_0974_),
    .B1(_0762_),
    .B2(a_out[2]),
    .X(_0975_));
 sky130_fd_sc_hd__xnor2_2 _1752_ (.A(_0758_),
    .B(_0975_),
    .Y(_0976_));
 sky130_fd_sc_hd__nand2_2 _1753_ (.A(_0973_),
    .B(_0976_),
    .Y(_0977_));
 sky130_fd_sc_hd__or2_2 _1754_ (.A(_0973_),
    .B(_0976_),
    .X(_0978_));
 sky130_fd_sc_hd__and2_2 _1755_ (.A(_0977_),
    .B(_0978_),
    .X(_0979_));
 sky130_fd_sc_hd__xnor2_2 _1756_ (.A(_0972_),
    .B(_0979_),
    .Y(_0980_));
 sky130_fd_sc_hd__xnor2_2 _1757_ (.A(_0779_),
    .B(_0980_),
    .Y(_0981_));
 sky130_fd_sc_hd__a32o_2 _1758_ (.A1(a_out[8]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[9]),
    .X(_0982_));
 sky130_fd_sc_hd__xor2_2 _1759_ (.A(\r2_mantissa[7] ),
    .B(_0982_),
    .X(_0983_));
 sky130_fd_sc_hd__a32o_2 _1760_ (.A1(a_out[6]),
    .A2(_0678_),
    .A3(_0643_),
    .B1(_0640_),
    .B2(a_out[7]),
    .X(_0984_));
 sky130_fd_sc_hd__xnor2_2 _1761_ (.A(_0677_),
    .B(_0984_),
    .Y(_0985_));
 sky130_fd_sc_hd__xor2_2 _1762_ (.A(_0983_),
    .B(_0985_),
    .X(_0986_));
 sky130_fd_sc_hd__a22o_2 _1763_ (.A1(a_out[5]),
    .A2(_0650_),
    .B1(_0654_),
    .B2(a_out[4]),
    .X(_0987_));
 sky130_fd_sc_hd__xnor2_2 _1764_ (.A(_0648_),
    .B(_0987_),
    .Y(_0988_));
 sky130_fd_sc_hd__and2_2 _1765_ (.A(_0986_),
    .B(_0988_),
    .X(_0989_));
 sky130_fd_sc_hd__nor2_2 _1766_ (.A(_0986_),
    .B(_0988_),
    .Y(_0990_));
 sky130_fd_sc_hd__nor2_2 _1767_ (.A(_0989_),
    .B(_0990_),
    .Y(_0991_));
 sky130_fd_sc_hd__nand3_2 _1768_ (.A(\r2_mantissa[1] ),
    .B(a_out[14]),
    .C(_0003_),
    .Y(_0992_));
 sky130_fd_sc_hd__a21o_2 _1769_ (.A1(a_out[14]),
    .A2(_0003_),
    .B1(\r2_mantissa[1] ),
    .X(_0993_));
 sky130_fd_sc_hd__nand2_2 _1770_ (.A(_0992_),
    .B(_0993_),
    .Y(_0994_));
 sky130_fd_sc_hd__a32o_2 _1771_ (.A1(a_out[12]),
    .A2(_0603_),
    .A3(_0604_),
    .B1(_0606_),
    .B2(a_out[13]),
    .X(_0995_));
 sky130_fd_sc_hd__xor2_2 _1772_ (.A(\r2_mantissa[3] ),
    .B(_0995_),
    .X(_0996_));
 sky130_fd_sc_hd__xnor2_2 _1773_ (.A(_0994_),
    .B(_0996_),
    .Y(_0997_));
 sky130_fd_sc_hd__a22o_2 _1774_ (.A1(a_out[11]),
    .A2(_0610_),
    .B1(_0614_),
    .B2(a_out[10]),
    .X(_0998_));
 sky130_fd_sc_hd__xor2_2 _1775_ (.A(\r2_mantissa[5] ),
    .B(_0998_),
    .X(_0999_));
 sky130_fd_sc_hd__xnor2_2 _1776_ (.A(_0997_),
    .B(_0999_),
    .Y(_1000_));
 sky130_fd_sc_hd__and2_2 _1777_ (.A(_0794_),
    .B(_0796_),
    .X(_1001_));
 sky130_fd_sc_hd__a21oi_2 _1778_ (.A1(_0797_),
    .A2(_0799_),
    .B1(_1001_),
    .Y(_1002_));
 sky130_fd_sc_hd__xnor2_2 _1779_ (.A(_1000_),
    .B(_1002_),
    .Y(_1003_));
 sky130_fd_sc_hd__xor2_2 _1780_ (.A(_0991_),
    .B(_1003_),
    .X(_1004_));
 sky130_fd_sc_hd__and2b_2 _1781_ (.A_N(_0802_),
    .B(_0800_),
    .X(_1005_));
 sky130_fd_sc_hd__a21oi_2 _1782_ (.A1(_0792_),
    .A2(_0803_),
    .B1(_1005_),
    .Y(_1006_));
 sky130_fd_sc_hd__xnor2_2 _1783_ (.A(_1004_),
    .B(_1006_),
    .Y(_1007_));
 sky130_fd_sc_hd__xor2_2 _1784_ (.A(_0981_),
    .B(_1007_),
    .X(_1008_));
 sky130_fd_sc_hd__or2_2 _1785_ (.A(_0804_),
    .B(_0806_),
    .X(_1009_));
 sky130_fd_sc_hd__o21a_2 _1786_ (.A1(_0782_),
    .A2(_0807_),
    .B1(_1009_),
    .X(_1010_));
 sky130_fd_sc_hd__xor2_2 _1787_ (.A(_1008_),
    .B(_1010_),
    .X(_1011_));
 sky130_fd_sc_hd__xnor2_2 _1788_ (.A(_0971_),
    .B(_1011_),
    .Y(_1012_));
 sky130_fd_sc_hd__xnor2_2 _1789_ (.A(_0970_),
    .B(_1012_),
    .Y(_1013_));
 sky130_fd_sc_hd__xnor2_2 _1790_ (.A(_0813_),
    .B(_1013_),
    .Y(_1014_));
 sky130_fd_sc_hd__a21oi_2 _1791_ (.A1(_0815_),
    .A2(_0968_),
    .B1(_1014_),
    .Y(_1015_));
 sky130_fd_sc_hd__or2_2 _1792_ (.A(_0594_),
    .B(clear_acc),
    .X(_1016_));
 sky130_fd_sc_hd__buf_1 _1793_ (.A(_1016_),
    .X(_1017_));
 sky130_fd_sc_hd__a31o_2 _1794_ (.A1(_1014_),
    .A2(_0815_),
    .A3(_0968_),
    .B1(_1017_),
    .X(_1018_));
 sky130_fd_sc_hd__o22a_2 _1795_ (.A1(enable),
    .A2(_0599_),
    .B1(_1015_),
    .B2(_1018_),
    .X(_1019_));
 sky130_fd_sc_hd__nor2_2 _1796_ (.A(reset),
    .B(_1019_),
    .Y(_0016_));
 sky130_fd_sc_hd__buf_1 _1797_ (.A(_0594_),
    .X(_1020_));
 sky130_fd_sc_hd__nor2_2 _1798_ (.A(_0772_),
    .B(_0812_),
    .Y(_1021_));
 sky130_fd_sc_hd__a32o_2 _1799_ (.A1(_1014_),
    .A2(_0815_),
    .A3(_0968_),
    .B1(_1013_),
    .B2(_1021_),
    .X(_1022_));
 sky130_fd_sc_hd__or2b_2 _1800_ (.A(_0970_),
    .B_N(_1012_),
    .X(_1023_));
 sky130_fd_sc_hd__and2b_2 _1801_ (.A_N(_1010_),
    .B(_1008_),
    .X(_1024_));
 sky130_fd_sc_hd__inv_2 _1802_ (.A(_0971_),
    .Y(_1025_));
 sky130_fd_sc_hd__nor2_2 _1803_ (.A(_1025_),
    .B(_1011_),
    .Y(_1026_));
 sky130_fd_sc_hd__nor2_2 _1804_ (.A(_0779_),
    .B(_0980_),
    .Y(_1027_));
 sky130_fd_sc_hd__a21oi_2 _1805_ (.A1(_0972_),
    .A2(_0979_),
    .B1(_1027_),
    .Y(_1028_));
 sky130_fd_sc_hd__a21o_2 _1806_ (.A1(_0983_),
    .A2(_0985_),
    .B1(_0989_),
    .X(_1029_));
 sky130_fd_sc_hd__a22o_2 _1807_ (.A1(a_out[2]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[1]),
    .X(_1030_));
 sky130_fd_sc_hd__a22o_2 _1808_ (.A1(a_out[4]),
    .A2(_0974_),
    .B1(_0762_),
    .B2(a_out[3]),
    .X(_1031_));
 sky130_fd_sc_hd__xnor2_2 _1809_ (.A(_0759_),
    .B(_1031_),
    .Y(_1032_));
 sky130_fd_sc_hd__nand2_2 _1810_ (.A(_1030_),
    .B(_1032_),
    .Y(_1033_));
 sky130_fd_sc_hd__or2_2 _1811_ (.A(_1030_),
    .B(_1032_),
    .X(_1034_));
 sky130_fd_sc_hd__and2_2 _1812_ (.A(_1033_),
    .B(_1034_),
    .X(_1035_));
 sky130_fd_sc_hd__xor2_2 _1813_ (.A(_1029_),
    .B(_1035_),
    .X(_1036_));
 sky130_fd_sc_hd__xor2_2 _1814_ (.A(_0977_),
    .B(_1036_),
    .X(_1037_));
 sky130_fd_sc_hd__a32o_2 _1815_ (.A1(a_out[9]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[10]),
    .X(_1038_));
 sky130_fd_sc_hd__xor2_2 _1816_ (.A(\r2_mantissa[7] ),
    .B(_1038_),
    .X(_1039_));
 sky130_fd_sc_hd__a32o_2 _1817_ (.A1(a_out[7]),
    .A2(_0678_),
    .A3(_0643_),
    .B1(_0640_),
    .B2(a_out[8]),
    .X(_1040_));
 sky130_fd_sc_hd__xnor2_2 _1818_ (.A(_0677_),
    .B(_1040_),
    .Y(_1041_));
 sky130_fd_sc_hd__and2_2 _1819_ (.A(_1039_),
    .B(_1041_),
    .X(_1042_));
 sky130_fd_sc_hd__nor2_2 _1820_ (.A(_1039_),
    .B(_1041_),
    .Y(_1043_));
 sky130_fd_sc_hd__nor2_2 _1821_ (.A(_1042_),
    .B(_1043_),
    .Y(_1044_));
 sky130_fd_sc_hd__a22o_2 _1822_ (.A1(a_out[6]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[5]),
    .X(_1045_));
 sky130_fd_sc_hd__xnor2_2 _1823_ (.A(_0685_),
    .B(_1045_),
    .Y(_1046_));
 sky130_fd_sc_hd__xor2_2 _1824_ (.A(_1044_),
    .B(_1046_),
    .X(_1047_));
 sky130_fd_sc_hd__a32o_2 _1825_ (.A1(a_out[13]),
    .A2(_0603_),
    .A3(_0604_),
    .B1(_0606_),
    .B2(a_out[14]),
    .X(_1048_));
 sky130_fd_sc_hd__xor2_2 _1826_ (.A(\r2_mantissa[3] ),
    .B(_1048_),
    .X(_1049_));
 sky130_fd_sc_hd__xnor2_2 _1827_ (.A(_0851_),
    .B(_1049_),
    .Y(_1050_));
 sky130_fd_sc_hd__a22o_2 _1828_ (.A1(a_out[12]),
    .A2(_0610_),
    .B1(_0614_),
    .B2(a_out[11]),
    .X(_1051_));
 sky130_fd_sc_hd__xor2_2 _1829_ (.A(\r2_mantissa[5] ),
    .B(_1051_),
    .X(_1052_));
 sky130_fd_sc_hd__xor2_2 _1830_ (.A(_1050_),
    .B(_1052_),
    .X(_1053_));
 sky130_fd_sc_hd__and3_2 _1831_ (.A(_0992_),
    .B(_0993_),
    .C(_0996_),
    .X(_1054_));
 sky130_fd_sc_hd__a21oi_2 _1832_ (.A1(_0997_),
    .A2(_0999_),
    .B1(_1054_),
    .Y(_1055_));
 sky130_fd_sc_hd__xnor2_2 _1833_ (.A(_1053_),
    .B(_1055_),
    .Y(_1056_));
 sky130_fd_sc_hd__xnor2_2 _1834_ (.A(_1047_),
    .B(_1056_),
    .Y(_1057_));
 sky130_fd_sc_hd__o32a_2 _1835_ (.A1(_0989_),
    .A2(_0990_),
    .A3(_1003_),
    .B1(_1002_),
    .B2(_1000_),
    .X(_1058_));
 sky130_fd_sc_hd__xnor2_2 _1836_ (.A(_1057_),
    .B(_1058_),
    .Y(_1059_));
 sky130_fd_sc_hd__xor2_2 _1837_ (.A(_1037_),
    .B(_1059_),
    .X(_1060_));
 sky130_fd_sc_hd__or2_2 _1838_ (.A(_1004_),
    .B(_1006_),
    .X(_1061_));
 sky130_fd_sc_hd__o21a_2 _1839_ (.A1(_0981_),
    .A2(_1007_),
    .B1(_1061_),
    .X(_1062_));
 sky130_fd_sc_hd__xnor2_2 _1840_ (.A(_1060_),
    .B(_1062_),
    .Y(_1063_));
 sky130_fd_sc_hd__xnor2_2 _1841_ (.A(_1028_),
    .B(_1063_),
    .Y(_1064_));
 sky130_fd_sc_hd__o21a_2 _1842_ (.A1(_1024_),
    .A2(_1026_),
    .B1(_1064_),
    .X(_1065_));
 sky130_fd_sc_hd__nor3_2 _1843_ (.A(_1024_),
    .B(_1026_),
    .C(_1064_),
    .Y(_1066_));
 sky130_fd_sc_hd__or2_2 _1844_ (.A(_1065_),
    .B(_1066_),
    .X(_1067_));
 sky130_fd_sc_hd__xor2_4 _1845_ (.A(_1023_),
    .B(_1067_),
    .X(_1068_));
 sky130_fd_sc_hd__xnor2_2 _1846_ (.A(_1022_),
    .B(_1068_),
    .Y(_1069_));
 sky130_fd_sc_hd__o2bb2a_2 _1847_ (.A1_N(_1020_),
    .A2_N(\r3_prod_mant[1] ),
    .B1(_1017_),
    .B2(_1069_),
    .X(_1070_));
 sky130_fd_sc_hd__nor2_2 _1848_ (.A(reset),
    .B(_1070_),
    .Y(_0017_));
 sky130_fd_sc_hd__inv_2 _1849_ (.A(\r3_prod_mant[2] ),
    .Y(_1071_));
 sky130_fd_sc_hd__or2b_2 _1850_ (.A(_1062_),
    .B_N(_1060_),
    .X(_1072_));
 sky130_fd_sc_hd__nand2b_2 _1851_ (.A_N(_1028_),
    .B(_1063_),
    .Y(_1073_));
 sky130_fd_sc_hd__a32o_2 _1852_ (.A1(_0973_),
    .A2(_0976_),
    .A3(_1036_),
    .B1(_1035_),
    .B2(_1029_),
    .X(_1074_));
 sky130_fd_sc_hd__a21o_2 _1853_ (.A1(_1044_),
    .A2(_1046_),
    .B1(_1042_),
    .X(_1075_));
 sky130_fd_sc_hd__a22o_2 _1854_ (.A1(a_out[3]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[2]),
    .X(_1076_));
 sky130_fd_sc_hd__a22o_2 _1855_ (.A1(a_out[5]),
    .A2(_0974_),
    .B1(_0762_),
    .B2(a_out[4]),
    .X(_1077_));
 sky130_fd_sc_hd__xnor2_2 _1856_ (.A(_0759_),
    .B(_1077_),
    .Y(_1078_));
 sky130_fd_sc_hd__nand2_2 _1857_ (.A(_1076_),
    .B(_1078_),
    .Y(_1079_));
 sky130_fd_sc_hd__or2_2 _1858_ (.A(_1076_),
    .B(_1078_),
    .X(_1080_));
 sky130_fd_sc_hd__and2_2 _1859_ (.A(_1079_),
    .B(_1080_),
    .X(_1081_));
 sky130_fd_sc_hd__xor2_2 _1860_ (.A(_1075_),
    .B(_1081_),
    .X(_1082_));
 sky130_fd_sc_hd__xor2_2 _1861_ (.A(_1033_),
    .B(_1082_),
    .X(_1083_));
 sky130_fd_sc_hd__a32o_2 _1862_ (.A1(a_out[10]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[11]),
    .X(_1084_));
 sky130_fd_sc_hd__xor2_2 _1863_ (.A(\r2_mantissa[7] ),
    .B(_1084_),
    .X(_1085_));
 sky130_fd_sc_hd__a32o_2 _1864_ (.A1(a_out[8]),
    .A2(_0642_),
    .A3(_0643_),
    .B1(_0640_),
    .B2(a_out[9]),
    .X(_1086_));
 sky130_fd_sc_hd__xnor2_2 _1865_ (.A(_0677_),
    .B(_1086_),
    .Y(_1087_));
 sky130_fd_sc_hd__and2_2 _1866_ (.A(_1085_),
    .B(_1087_),
    .X(_1088_));
 sky130_fd_sc_hd__nor2_2 _1867_ (.A(_1085_),
    .B(_1087_),
    .Y(_1089_));
 sky130_fd_sc_hd__nor2_2 _1868_ (.A(_1088_),
    .B(_1089_),
    .Y(_1090_));
 sky130_fd_sc_hd__a22o_2 _1869_ (.A1(a_out[7]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[6]),
    .X(_1091_));
 sky130_fd_sc_hd__xnor2_2 _1870_ (.A(_0685_),
    .B(_1091_),
    .Y(_1092_));
 sky130_fd_sc_hd__xor2_2 _1871_ (.A(_1090_),
    .B(_1092_),
    .X(_1093_));
 sky130_fd_sc_hd__inv_2 _1872_ (.A(_0826_),
    .Y(_1094_));
 sky130_fd_sc_hd__or2_2 _1873_ (.A(\r2_mantissa[3] ),
    .B(\r2_mantissa[1] ),
    .X(_1095_));
 sky130_fd_sc_hd__nand2_2 _1874_ (.A(\r2_mantissa[3] ),
    .B(\r2_mantissa[1] ),
    .Y(_1096_));
 sky130_fd_sc_hd__nand2_2 _1875_ (.A(_1095_),
    .B(_1096_),
    .Y(_1097_));
 sky130_fd_sc_hd__a21oi_2 _1876_ (.A1(a_out[14]),
    .A2(_1094_),
    .B1(_1097_),
    .Y(_1098_));
 sky130_fd_sc_hd__a32o_2 _1877_ (.A1(a_out[12]),
    .A2(_0612_),
    .A3(_0613_),
    .B1(_0610_),
    .B2(a_out[13]),
    .X(_1099_));
 sky130_fd_sc_hd__xor2_2 _1878_ (.A(\r2_mantissa[5] ),
    .B(_1099_),
    .X(_1100_));
 sky130_fd_sc_hd__and2_2 _1879_ (.A(_1098_),
    .B(_1100_),
    .X(_1101_));
 sky130_fd_sc_hd__nor2_2 _1880_ (.A(_1098_),
    .B(_1100_),
    .Y(_1102_));
 sky130_fd_sc_hd__or2_2 _1881_ (.A(_1101_),
    .B(_1102_),
    .X(_1103_));
 sky130_fd_sc_hd__and2_2 _1882_ (.A(\r2_mantissa[1] ),
    .B(_1049_),
    .X(_1104_));
 sky130_fd_sc_hd__a21oi_2 _1883_ (.A1(_1050_),
    .A2(_1052_),
    .B1(_1104_),
    .Y(_1105_));
 sky130_fd_sc_hd__xor2_2 _1884_ (.A(_1103_),
    .B(_1105_),
    .X(_1106_));
 sky130_fd_sc_hd__xnor2_2 _1885_ (.A(_1093_),
    .B(_1106_),
    .Y(_1107_));
 sky130_fd_sc_hd__and2b_2 _1886_ (.A_N(_1055_),
    .B(_1053_),
    .X(_1108_));
 sky130_fd_sc_hd__a21oi_2 _1887_ (.A1(_1047_),
    .A2(_1056_),
    .B1(_1108_),
    .Y(_1109_));
 sky130_fd_sc_hd__xnor2_2 _1888_ (.A(_1107_),
    .B(_1109_),
    .Y(_1110_));
 sky130_fd_sc_hd__xor2_2 _1889_ (.A(_1083_),
    .B(_1110_),
    .X(_1111_));
 sky130_fd_sc_hd__or2_2 _1890_ (.A(_1057_),
    .B(_1058_),
    .X(_1112_));
 sky130_fd_sc_hd__o21a_2 _1891_ (.A1(_1037_),
    .A2(_1059_),
    .B1(_1112_),
    .X(_1113_));
 sky130_fd_sc_hd__xnor2_2 _1892_ (.A(_1111_),
    .B(_1113_),
    .Y(_1114_));
 sky130_fd_sc_hd__xnor2_2 _1893_ (.A(_1074_),
    .B(_1114_),
    .Y(_1115_));
 sky130_fd_sc_hd__a21oi_2 _1894_ (.A1(_1072_),
    .A2(_1073_),
    .B1(_1115_),
    .Y(_1116_));
 sky130_fd_sc_hd__and3_2 _1895_ (.A(_1072_),
    .B(_1073_),
    .C(_1115_),
    .X(_1117_));
 sky130_fd_sc_hd__nor2_2 _1896_ (.A(_1116_),
    .B(_1117_),
    .Y(_1118_));
 sky130_fd_sc_hd__xnor2_2 _1897_ (.A(_1065_),
    .B(_1118_),
    .Y(_1119_));
 sky130_fd_sc_hd__nor2_2 _1898_ (.A(_1023_),
    .B(_1067_),
    .Y(_1120_));
 sky130_fd_sc_hd__a21oi_2 _1899_ (.A1(_1022_),
    .A2(_1068_),
    .B1(_1120_),
    .Y(_1121_));
 sky130_fd_sc_hd__nor2_2 _1900_ (.A(_1119_),
    .B(_1121_),
    .Y(_1122_));
 sky130_fd_sc_hd__a21o_2 _1901_ (.A1(_1119_),
    .A2(_1121_),
    .B1(_1017_),
    .X(_1123_));
 sky130_fd_sc_hd__o22a_2 _1902_ (.A1(enable),
    .A2(_1071_),
    .B1(_1122_),
    .B2(_1123_),
    .X(_1124_));
 sky130_fd_sc_hd__nor2_2 _1903_ (.A(reset),
    .B(_1124_),
    .Y(_0018_));
 sky130_fd_sc_hd__and2b_2 _1904_ (.A_N(_1113_),
    .B(_1111_),
    .X(_1125_));
 sky130_fd_sc_hd__a21oi_2 _1905_ (.A1(_1074_),
    .A2(_1114_),
    .B1(_1125_),
    .Y(_1126_));
 sky130_fd_sc_hd__a32o_2 _1906_ (.A1(_1030_),
    .A2(_1032_),
    .A3(_1082_),
    .B1(_1081_),
    .B2(_1075_),
    .X(_1127_));
 sky130_fd_sc_hd__a21o_2 _1907_ (.A1(_1090_),
    .A2(_1092_),
    .B1(_1088_),
    .X(_1128_));
 sky130_fd_sc_hd__a22o_2 _1908_ (.A1(a_out[4]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[3]),
    .X(_1129_));
 sky130_fd_sc_hd__a22o_2 _1909_ (.A1(a_out[6]),
    .A2(_0974_),
    .B1(_0762_),
    .B2(a_out[5]),
    .X(_1130_));
 sky130_fd_sc_hd__xnor2_2 _1910_ (.A(_0759_),
    .B(_1130_),
    .Y(_1131_));
 sky130_fd_sc_hd__nand2_2 _1911_ (.A(_1129_),
    .B(_1131_),
    .Y(_1132_));
 sky130_fd_sc_hd__or2_2 _1912_ (.A(_1129_),
    .B(_1131_),
    .X(_1133_));
 sky130_fd_sc_hd__and2_2 _1913_ (.A(_1132_),
    .B(_1133_),
    .X(_1134_));
 sky130_fd_sc_hd__xor2_2 _1914_ (.A(_1128_),
    .B(_1134_),
    .X(_1135_));
 sky130_fd_sc_hd__xor2_2 _1915_ (.A(_1079_),
    .B(_1135_),
    .X(_1136_));
 sky130_fd_sc_hd__a32o_2 _1916_ (.A1(a_out[11]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0632_),
    .B2(a_out[12]),
    .X(_1137_));
 sky130_fd_sc_hd__xor2_2 _1917_ (.A(\r2_mantissa[7] ),
    .B(_1137_),
    .X(_1138_));
 sky130_fd_sc_hd__a32o_2 _1918_ (.A1(a_out[9]),
    .A2(_0678_),
    .A3(_0679_),
    .B1(_0641_),
    .B2(a_out[10]),
    .X(_1139_));
 sky130_fd_sc_hd__xnor2_2 _1919_ (.A(_0639_),
    .B(_1139_),
    .Y(_1140_));
 sky130_fd_sc_hd__xor2_2 _1920_ (.A(_1138_),
    .B(_1140_),
    .X(_1141_));
 sky130_fd_sc_hd__a22o_2 _1921_ (.A1(a_out[8]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[7]),
    .X(_1142_));
 sky130_fd_sc_hd__xnor2_2 _1922_ (.A(_0685_),
    .B(_1142_),
    .Y(_1143_));
 sky130_fd_sc_hd__xor2_2 _1923_ (.A(_1141_),
    .B(_1143_),
    .X(_1144_));
 sky130_fd_sc_hd__and2_2 _1924_ (.A(\r2_mantissa[3] ),
    .B(\r2_mantissa[1] ),
    .X(_1145_));
 sky130_fd_sc_hd__and3_2 _1925_ (.A(\r2_mantissa[2] ),
    .B(\r2_mantissa[1] ),
    .C(a_out[14]),
    .X(_1146_));
 sky130_fd_sc_hd__a32o_2 _1926_ (.A1(a_out[13]),
    .A2(_0612_),
    .A3(_0613_),
    .B1(_0610_),
    .B2(a_out[14]),
    .X(_1147_));
 sky130_fd_sc_hd__xor2_2 _1927_ (.A(\r2_mantissa[5] ),
    .B(_1147_),
    .X(_1148_));
 sky130_fd_sc_hd__xnor2_2 _1928_ (.A(_1097_),
    .B(_1148_),
    .Y(_1149_));
 sky130_fd_sc_hd__o31a_2 _1929_ (.A1(_1145_),
    .A2(_1101_),
    .A3(_1146_),
    .B1(_1149_),
    .X(_1150_));
 sky130_fd_sc_hd__or4_4 _1930_ (.A(_1145_),
    .B(_1101_),
    .C(_1149_),
    .D(_1146_),
    .X(_1151_));
 sky130_fd_sc_hd__nor2b_2 _1931_ (.A(_1150_),
    .B_N(_1151_),
    .Y(_1152_));
 sky130_fd_sc_hd__xnor2_2 _1932_ (.A(_1144_),
    .B(_1152_),
    .Y(_1153_));
 sky130_fd_sc_hd__nor2_2 _1933_ (.A(_1103_),
    .B(_1105_),
    .Y(_1154_));
 sky130_fd_sc_hd__a21oi_2 _1934_ (.A1(_1093_),
    .A2(_1106_),
    .B1(_1154_),
    .Y(_1155_));
 sky130_fd_sc_hd__xnor2_2 _1935_ (.A(_1153_),
    .B(_1155_),
    .Y(_1156_));
 sky130_fd_sc_hd__xor2_2 _1936_ (.A(_1136_),
    .B(_1156_),
    .X(_1157_));
 sky130_fd_sc_hd__or2_2 _1937_ (.A(_1107_),
    .B(_1109_),
    .X(_1158_));
 sky130_fd_sc_hd__o21ai_2 _1938_ (.A1(_1083_),
    .A2(_1110_),
    .B1(_1158_),
    .Y(_1159_));
 sky130_fd_sc_hd__xor2_2 _1939_ (.A(_1157_),
    .B(_1159_),
    .X(_1160_));
 sky130_fd_sc_hd__xor2_2 _1940_ (.A(_1127_),
    .B(_1160_),
    .X(_1161_));
 sky130_fd_sc_hd__xnor2_2 _1941_ (.A(_1126_),
    .B(_1161_),
    .Y(_1162_));
 sky130_fd_sc_hd__nand2_2 _1942_ (.A(_1116_),
    .B(_1162_),
    .Y(_1163_));
 sky130_fd_sc_hd__or2_2 _1943_ (.A(_1116_),
    .B(_1162_),
    .X(_1164_));
 sky130_fd_sc_hd__and2_2 _1944_ (.A(_1163_),
    .B(_1164_),
    .X(_1165_));
 sky130_fd_sc_hd__a211oi_2 _1945_ (.A1(_1065_),
    .A2(_1118_),
    .B1(_1122_),
    .C1(_1165_),
    .Y(_1166_));
 sky130_fd_sc_hd__and2_2 _1946_ (.A(_1122_),
    .B(_1165_),
    .X(_1167_));
 sky130_fd_sc_hd__nand4bb_2 _1947_ (.A_N(_1116_),
    .B_N(_1117_),
    .C(_1162_),
    .D(_1065_),
    .Y(_1168_));
 sky130_fd_sc_hd__nand2_2 _1948_ (.A(_0596_),
    .B(_1168_),
    .Y(_1169_));
 sky130_fd_sc_hd__inv_2 _1949_ (.A(\r3_prod_mant[3] ),
    .Y(_1170_));
 sky130_fd_sc_hd__o32a_2 _1950_ (.A1(_1166_),
    .A2(_1167_),
    .A3(_1169_),
    .B1(_1170_),
    .B2(enable),
    .X(_1171_));
 sky130_fd_sc_hd__nor2_2 _1951_ (.A(reset),
    .B(_1171_),
    .Y(_0019_));
 sky130_fd_sc_hd__buf_1 _1952_ (.A(_0577_),
    .X(_1172_));
 sky130_fd_sc_hd__nand2_2 _1953_ (.A(_1163_),
    .B(_1168_),
    .Y(_1173_));
 sky130_fd_sc_hd__and2b_2 _1954_ (.A_N(_1126_),
    .B(_1161_),
    .X(_1174_));
 sky130_fd_sc_hd__and2_2 _1955_ (.A(_1157_),
    .B(_1159_),
    .X(_1175_));
 sky130_fd_sc_hd__a21o_2 _1956_ (.A1(_1127_),
    .A2(_1160_),
    .B1(_1175_),
    .X(_1176_));
 sky130_fd_sc_hd__a32o_2 _1957_ (.A1(_1076_),
    .A2(_1078_),
    .A3(_1135_),
    .B1(_1134_),
    .B2(_1128_),
    .X(_1177_));
 sky130_fd_sc_hd__and2_2 _1958_ (.A(_1138_),
    .B(_1140_),
    .X(_1178_));
 sky130_fd_sc_hd__a21o_2 _1959_ (.A1(_1141_),
    .A2(_1143_),
    .B1(_1178_),
    .X(_1179_));
 sky130_fd_sc_hd__a22o_2 _1960_ (.A1(a_out[5]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[4]),
    .X(_1180_));
 sky130_fd_sc_hd__a22o_2 _1961_ (.A1(a_out[7]),
    .A2(_0694_),
    .B1(_0763_),
    .B2(a_out[6]),
    .X(_1181_));
 sky130_fd_sc_hd__xnor2_2 _1962_ (.A(_0760_),
    .B(_1181_),
    .Y(_1182_));
 sky130_fd_sc_hd__xor2_2 _1963_ (.A(_1180_),
    .B(_1182_),
    .X(_1183_));
 sky130_fd_sc_hd__xor2_2 _1964_ (.A(_1179_),
    .B(_1183_),
    .X(_1184_));
 sky130_fd_sc_hd__xor2_2 _1965_ (.A(_1132_),
    .B(_1184_),
    .X(_1185_));
 sky130_fd_sc_hd__a32o_2 _1966_ (.A1(a_out[12]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[13]),
    .X(_1186_));
 sky130_fd_sc_hd__xor2_2 _1967_ (.A(\r2_mantissa[7] ),
    .B(_1186_),
    .X(_1187_));
 sky130_fd_sc_hd__a32o_2 _1968_ (.A1(a_out[10]),
    .A2(_0678_),
    .A3(_0679_),
    .B1(_0640_),
    .B2(a_out[11]),
    .X(_1188_));
 sky130_fd_sc_hd__xnor2_2 _1969_ (.A(_0677_),
    .B(_1188_),
    .Y(_1189_));
 sky130_fd_sc_hd__xor2_2 _1970_ (.A(_1187_),
    .B(_1189_),
    .X(_1190_));
 sky130_fd_sc_hd__a22o_2 _1971_ (.A1(a_out[9]),
    .A2(_0650_),
    .B1(_0654_),
    .B2(a_out[8]),
    .X(_1191_));
 sky130_fd_sc_hd__xnor2_2 _1972_ (.A(_0648_),
    .B(_1191_),
    .Y(_1192_));
 sky130_fd_sc_hd__xor2_2 _1973_ (.A(_1190_),
    .B(_1192_),
    .X(_1193_));
 sky130_fd_sc_hd__and2_2 _1974_ (.A(_1095_),
    .B(_1096_),
    .X(_1194_));
 sky130_fd_sc_hd__or3b_2 _1975_ (.A(\r2_mantissa[3] ),
    .B(\r2_mantissa[4] ),
    .C_N(a_out[14]),
    .X(_1195_));
 sky130_fd_sc_hd__and4b_2 _1976_ (.A_N(\r2_mantissa[5] ),
    .B(\r2_mantissa[4] ),
    .C(\r2_mantissa[3] ),
    .D(a_out[14]),
    .X(_1196_));
 sky130_fd_sc_hd__a21o_2 _1977_ (.A1(\r2_mantissa[5] ),
    .A2(_1195_),
    .B1(_1196_),
    .X(_1197_));
 sky130_fd_sc_hd__nand2_2 _1978_ (.A(_1194_),
    .B(_1197_),
    .Y(_1198_));
 sky130_fd_sc_hd__or2_2 _1979_ (.A(_1194_),
    .B(_1197_),
    .X(_1199_));
 sky130_fd_sc_hd__nand2_2 _1980_ (.A(_1198_),
    .B(_1199_),
    .Y(_1200_));
 sky130_fd_sc_hd__a21oi_2 _1981_ (.A1(_1194_),
    .A2(_1148_),
    .B1(_1145_),
    .Y(_1201_));
 sky130_fd_sc_hd__xor2_2 _1982_ (.A(_1200_),
    .B(_1201_),
    .X(_1202_));
 sky130_fd_sc_hd__xnor2_2 _1983_ (.A(_1193_),
    .B(_1202_),
    .Y(_1203_));
 sky130_fd_sc_hd__a21oi_2 _1984_ (.A1(_1144_),
    .A2(_1151_),
    .B1(_1150_),
    .Y(_1204_));
 sky130_fd_sc_hd__xor2_2 _1985_ (.A(_1203_),
    .B(_1204_),
    .X(_1205_));
 sky130_fd_sc_hd__xnor2_2 _1986_ (.A(_1185_),
    .B(_1205_),
    .Y(_1206_));
 sky130_fd_sc_hd__or2_2 _1987_ (.A(_1153_),
    .B(_1155_),
    .X(_1207_));
 sky130_fd_sc_hd__o21a_2 _1988_ (.A1(_1136_),
    .A2(_1156_),
    .B1(_1207_),
    .X(_1208_));
 sky130_fd_sc_hd__xnor2_2 _1989_ (.A(_1206_),
    .B(_1208_),
    .Y(_1209_));
 sky130_fd_sc_hd__xnor2_2 _1990_ (.A(_1177_),
    .B(_1209_),
    .Y(_1210_));
 sky130_fd_sc_hd__xnor2_2 _1991_ (.A(_1176_),
    .B(_1210_),
    .Y(_1211_));
 sky130_fd_sc_hd__xnor2_2 _1992_ (.A(_1174_),
    .B(_1211_),
    .Y(_1212_));
 sky130_fd_sc_hd__o21bai_2 _1993_ (.A1(_1167_),
    .A2(_1173_),
    .B1_N(_1212_),
    .Y(_1213_));
 sky130_fd_sc_hd__or3b_2 _1994_ (.A(_1167_),
    .B(_1173_),
    .C_N(_1212_),
    .X(_1214_));
 sky130_fd_sc_hd__a32o_2 _1995_ (.A1(_0596_),
    .A2(_1213_),
    .A3(_1214_),
    .B1(\r3_prod_mant[4] ),
    .B2(_1020_),
    .X(_1215_));
 sky130_fd_sc_hd__and2_2 _1996_ (.A(_1172_),
    .B(_1215_),
    .X(_1216_));
 sky130_fd_sc_hd__buf_2 _1997_ (.A(_1216_),
    .X(_0020_));
 sky130_fd_sc_hd__nand2_2 _1998_ (.A(_1174_),
    .B(_1211_),
    .Y(_1217_));
 sky130_fd_sc_hd__nor2b_2 _1999_ (.A(_1210_),
    .B_N(_1176_),
    .Y(_1218_));
 sky130_fd_sc_hd__and2b_2 _2000_ (.A_N(_1208_),
    .B(_1206_),
    .X(_1219_));
 sky130_fd_sc_hd__a21o_2 _2001_ (.A1(_1177_),
    .A2(_1209_),
    .B1(_1219_),
    .X(_1220_));
 sky130_fd_sc_hd__a32o_2 _2002_ (.A1(_1129_),
    .A2(_1131_),
    .A3(_1184_),
    .B1(_1183_),
    .B2(_1179_),
    .X(_1221_));
 sky130_fd_sc_hd__nor2_2 _2003_ (.A(_1203_),
    .B(_1204_),
    .Y(_1222_));
 sky130_fd_sc_hd__nor2b_2 _2004_ (.A(_1185_),
    .B_N(_1205_),
    .Y(_1223_));
 sky130_fd_sc_hd__nand2_2 _2005_ (.A(_1180_),
    .B(_1182_),
    .Y(_1224_));
 sky130_fd_sc_hd__and2_2 _2006_ (.A(_1187_),
    .B(_1189_),
    .X(_1225_));
 sky130_fd_sc_hd__a21o_2 _2007_ (.A1(_1190_),
    .A2(_1192_),
    .B1(_1225_),
    .X(_1226_));
 sky130_fd_sc_hd__a22o_2 _2008_ (.A1(a_out[6]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[5]),
    .X(_1227_));
 sky130_fd_sc_hd__a22o_2 _2009_ (.A1(a_out[8]),
    .A2(_0694_),
    .B1(_0763_),
    .B2(a_out[7]),
    .X(_1228_));
 sky130_fd_sc_hd__xnor2_2 _2010_ (.A(_0760_),
    .B(_1228_),
    .Y(_1229_));
 sky130_fd_sc_hd__xor2_2 _2011_ (.A(_1227_),
    .B(_1229_),
    .X(_1230_));
 sky130_fd_sc_hd__xor2_2 _2012_ (.A(_1226_),
    .B(_1230_),
    .X(_1231_));
 sky130_fd_sc_hd__xnor2_2 _2013_ (.A(_1224_),
    .B(_1231_),
    .Y(_1232_));
 sky130_fd_sc_hd__a21oi_2 _2014_ (.A1(_1095_),
    .A2(_1198_),
    .B1(\r2_mantissa[5] ),
    .Y(_1233_));
 sky130_fd_sc_hd__nand3_2 _2015_ (.A(\r2_mantissa[5] ),
    .B(_1095_),
    .C(_1198_),
    .Y(_1234_));
 sky130_fd_sc_hd__or2b_2 _2016_ (.A(_1233_),
    .B_N(_1234_),
    .X(_1235_));
 sky130_fd_sc_hd__a32o_2 _2017_ (.A1(a_out[13]),
    .A2(_0672_),
    .A3(_0673_),
    .B1(_0674_),
    .B2(a_out[14]),
    .X(_1236_));
 sky130_fd_sc_hd__xor2_2 _2018_ (.A(\r2_mantissa[7] ),
    .B(_1236_),
    .X(_1237_));
 sky130_fd_sc_hd__a32o_2 _2019_ (.A1(a_out[11]),
    .A2(_0678_),
    .A3(_0679_),
    .B1(_0641_),
    .B2(a_out[12]),
    .X(_1238_));
 sky130_fd_sc_hd__xnor2_2 _2020_ (.A(_0639_),
    .B(_1238_),
    .Y(_1239_));
 sky130_fd_sc_hd__xor2_2 _2021_ (.A(_1237_),
    .B(_1239_),
    .X(_1240_));
 sky130_fd_sc_hd__a22o_2 _2022_ (.A1(a_out[10]),
    .A2(_0650_),
    .B1(_0655_),
    .B2(a_out[9]),
    .X(_1241_));
 sky130_fd_sc_hd__xnor2_2 _2023_ (.A(_0685_),
    .B(_1241_),
    .Y(_1242_));
 sky130_fd_sc_hd__xor2_2 _2024_ (.A(_1240_),
    .B(_1242_),
    .X(_1243_));
 sky130_fd_sc_hd__xnor2_2 _2025_ (.A(_1235_),
    .B(_1243_),
    .Y(_1244_));
 sky130_fd_sc_hd__nor2_2 _2026_ (.A(_1200_),
    .B(_1201_),
    .Y(_1245_));
 sky130_fd_sc_hd__a21oi_2 _2027_ (.A1(_1193_),
    .A2(_1202_),
    .B1(_1245_),
    .Y(_1246_));
 sky130_fd_sc_hd__xnor2_2 _2028_ (.A(_1244_),
    .B(_1246_),
    .Y(_1247_));
 sky130_fd_sc_hd__xor2_2 _2029_ (.A(_1232_),
    .B(_1247_),
    .X(_1248_));
 sky130_fd_sc_hd__o21a_2 _2030_ (.A1(_1222_),
    .A2(_1223_),
    .B1(_1248_),
    .X(_1249_));
 sky130_fd_sc_hd__nor3_2 _2031_ (.A(_1222_),
    .B(_1223_),
    .C(_1248_),
    .Y(_1250_));
 sky130_fd_sc_hd__nor2_2 _2032_ (.A(_1249_),
    .B(_1250_),
    .Y(_1251_));
 sky130_fd_sc_hd__xor2_2 _2033_ (.A(_1221_),
    .B(_1251_),
    .X(_1252_));
 sky130_fd_sc_hd__xor2_2 _2034_ (.A(_1220_),
    .B(_1252_),
    .X(_1253_));
 sky130_fd_sc_hd__xnor2_2 _2035_ (.A(_1218_),
    .B(_1253_),
    .Y(_1254_));
 sky130_fd_sc_hd__a21oi_2 _2036_ (.A1(_1217_),
    .A2(_1213_),
    .B1(_1254_),
    .Y(_1255_));
 sky130_fd_sc_hd__a31o_2 _2037_ (.A1(_1217_),
    .A2(_1213_),
    .A3(_1254_),
    .B1(_1016_),
    .X(_1256_));
 sky130_fd_sc_hd__o2bb2a_2 _2038_ (.A1_N(_1020_),
    .A2_N(\r3_prod_mant[5] ),
    .B1(_1255_),
    .B2(_1256_),
    .X(_1257_));
 sky130_fd_sc_hd__nor2_2 _2039_ (.A(reset),
    .B(_1257_),
    .Y(_0021_));
 sky130_fd_sc_hd__nand2_2 _2040_ (.A(_1220_),
    .B(_1252_),
    .Y(_1258_));
 sky130_fd_sc_hd__a21o_2 _2041_ (.A1(_1221_),
    .A2(_1251_),
    .B1(_1249_),
    .X(_1259_));
 sky130_fd_sc_hd__a32o_2 _2042_ (.A1(_1180_),
    .A2(_1182_),
    .A3(_1231_),
    .B1(_1230_),
    .B2(_1226_),
    .X(_1260_));
 sky130_fd_sc_hd__or3b_2 _2043_ (.A(\r2_mantissa[6] ),
    .B(\r2_mantissa[5] ),
    .C_N(a_out[14]),
    .X(_1261_));
 sky130_fd_sc_hd__and4b_2 _2044_ (.A_N(\r2_mantissa[7] ),
    .B(\r2_mantissa[6] ),
    .C(\r2_mantissa[5] ),
    .D(a_out[14]),
    .X(_1262_));
 sky130_fd_sc_hd__a21o_2 _2045_ (.A1(\r2_mantissa[7] ),
    .A2(_1261_),
    .B1(_1262_),
    .X(_1263_));
 sky130_fd_sc_hd__a32o_2 _2046_ (.A1(a_out[12]),
    .A2(_0678_),
    .A3(_0679_),
    .B1(_0640_),
    .B2(a_out[13]),
    .X(_1264_));
 sky130_fd_sc_hd__xnor2_2 _2047_ (.A(_0677_),
    .B(_1264_),
    .Y(_1265_));
 sky130_fd_sc_hd__xor2_2 _2048_ (.A(_1263_),
    .B(_1265_),
    .X(_1266_));
 sky130_fd_sc_hd__a22o_2 _2049_ (.A1(a_out[11]),
    .A2(_0650_),
    .B1(_0654_),
    .B2(a_out[10]),
    .X(_1267_));
 sky130_fd_sc_hd__xnor2_2 _2050_ (.A(_0648_),
    .B(_1267_),
    .Y(_1268_));
 sky130_fd_sc_hd__xor2_2 _2051_ (.A(_1266_),
    .B(_1268_),
    .X(_1269_));
 sky130_fd_sc_hd__a21oi_2 _2052_ (.A1(_1234_),
    .A2(_1243_),
    .B1(_1233_),
    .Y(_1270_));
 sky130_fd_sc_hd__xnor2_2 _2053_ (.A(_1269_),
    .B(_1270_),
    .Y(_1271_));
 sky130_fd_sc_hd__nand2_2 _2054_ (.A(_1227_),
    .B(_1229_),
    .Y(_1272_));
 sky130_fd_sc_hd__and2_2 _2055_ (.A(_1237_),
    .B(_1239_),
    .X(_1273_));
 sky130_fd_sc_hd__a21o_2 _2056_ (.A1(_1240_),
    .A2(_1242_),
    .B1(_1273_),
    .X(_1274_));
 sky130_fd_sc_hd__a22o_2 _2057_ (.A1(a_out[7]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[6]),
    .X(_1275_));
 sky130_fd_sc_hd__a22o_2 _2058_ (.A1(a_out[9]),
    .A2(_0974_),
    .B1(_0763_),
    .B2(a_out[8]),
    .X(_1276_));
 sky130_fd_sc_hd__xnor2_2 _2059_ (.A(_0759_),
    .B(_1276_),
    .Y(_1277_));
 sky130_fd_sc_hd__xor2_2 _2060_ (.A(_1275_),
    .B(_1277_),
    .X(_1278_));
 sky130_fd_sc_hd__xor2_2 _2061_ (.A(_1274_),
    .B(_1278_),
    .X(_1279_));
 sky130_fd_sc_hd__xor2_2 _2062_ (.A(_1272_),
    .B(_1279_),
    .X(_1280_));
 sky130_fd_sc_hd__xnor2_2 _2063_ (.A(_1271_),
    .B(_1280_),
    .Y(_1281_));
 sky130_fd_sc_hd__or2b_2 _2064_ (.A(_1246_),
    .B_N(_1244_),
    .X(_1282_));
 sky130_fd_sc_hd__a21boi_2 _2065_ (.A1(_1232_),
    .A2(_1247_),
    .B1_N(_1282_),
    .Y(_1283_));
 sky130_fd_sc_hd__xor2_2 _2066_ (.A(_1281_),
    .B(_1283_),
    .X(_1284_));
 sky130_fd_sc_hd__xnor2_2 _2067_ (.A(_1260_),
    .B(_1284_),
    .Y(_1285_));
 sky130_fd_sc_hd__xnor2_2 _2068_ (.A(_1259_),
    .B(_1285_),
    .Y(_1286_));
 sky130_fd_sc_hd__xnor2_2 _2069_ (.A(_1258_),
    .B(_1286_),
    .Y(_1287_));
 sky130_fd_sc_hd__nor2_2 _2070_ (.A(_1212_),
    .B(_1254_),
    .Y(_1288_));
 sky130_fd_sc_hd__nand3b_2 _2071_ (.A_N(_1119_),
    .B(_1165_),
    .C(_1288_),
    .Y(_1289_));
 sky130_fd_sc_hd__a211o_2 _2072_ (.A1(_1163_),
    .A2(_1168_),
    .B1(_1212_),
    .C1(_1254_),
    .X(_1290_));
 sky130_fd_sc_hd__o211a_2 _2073_ (.A1(_1218_),
    .A2(_1253_),
    .B1(_1211_),
    .C1(_1174_),
    .X(_1291_));
 sky130_fd_sc_hd__a21oi_2 _2074_ (.A1(_1218_),
    .A2(_1253_),
    .B1(_1291_),
    .Y(_1292_));
 sky130_fd_sc_hd__o211ai_2 _2075_ (.A1(_1121_),
    .A2(_1289_),
    .B1(_1290_),
    .C1(_1292_),
    .Y(_1293_));
 sky130_fd_sc_hd__and2_2 _2076_ (.A(_1287_),
    .B(_1293_),
    .X(_1294_));
 sky130_fd_sc_hd__o21ai_2 _2077_ (.A1(_1287_),
    .A2(_1293_),
    .B1(_0596_),
    .Y(_1295_));
 sky130_fd_sc_hd__o2bb2a_2 _2078_ (.A1_N(_1020_),
    .A2_N(\r3_prod_mant[6] ),
    .B1(_1294_),
    .B2(_1295_),
    .X(_1296_));
 sky130_fd_sc_hd__nor2_2 _2079_ (.A(reset),
    .B(_1296_),
    .Y(_0022_));
 sky130_fd_sc_hd__buf_1 _2080_ (.A(_1020_),
    .X(_1297_));
 sky130_fd_sc_hd__nand2_2 _2081_ (.A(_1297_),
    .B(\r3_prod_mant[7] ),
    .Y(_1298_));
 sky130_fd_sc_hd__nand2b_2 _2082_ (.A_N(_1285_),
    .B(_1259_),
    .Y(_1299_));
 sky130_fd_sc_hd__a32o_2 _2083_ (.A1(a_out[13]),
    .A2(_0678_),
    .A3(_0679_),
    .B1(_0641_),
    .B2(a_out[14]),
    .X(_1300_));
 sky130_fd_sc_hd__xnor2_2 _2084_ (.A(_0677_),
    .B(_1300_),
    .Y(_1301_));
 sky130_fd_sc_hd__xor2_2 _2085_ (.A(\r2_mantissa[7] ),
    .B(_1301_),
    .X(_1302_));
 sky130_fd_sc_hd__a22o_2 _2086_ (.A1(a_out[12]),
    .A2(_0650_),
    .B1(_0654_),
    .B2(a_out[11]),
    .X(_0086_));
 sky130_fd_sc_hd__xnor2_2 _2087_ (.A(_0685_),
    .B(_0086_),
    .Y(_0087_));
 sky130_fd_sc_hd__xor2_2 _2088_ (.A(_1302_),
    .B(_0087_),
    .X(_0088_));
 sky130_fd_sc_hd__or2b_2 _2089_ (.A(_1269_),
    .B_N(_0088_),
    .X(_0089_));
 sky130_fd_sc_hd__nand2b_2 _2090_ (.A_N(_0088_),
    .B(_1269_),
    .Y(_0090_));
 sky130_fd_sc_hd__nand2_2 _2091_ (.A(_0089_),
    .B(_0090_),
    .Y(_0091_));
 sky130_fd_sc_hd__nand2_2 _2092_ (.A(_1275_),
    .B(_1277_),
    .Y(_0092_));
 sky130_fd_sc_hd__nand2_2 _2093_ (.A(_1263_),
    .B(_1265_),
    .Y(_0093_));
 sky130_fd_sc_hd__a21bo_2 _2094_ (.A1(_1266_),
    .A2(_1268_),
    .B1_N(_0093_),
    .X(_0094_));
 sky130_fd_sc_hd__a22o_2 _2095_ (.A1(a_out[8]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[7]),
    .X(_0095_));
 sky130_fd_sc_hd__a22o_2 _2096_ (.A1(a_out[10]),
    .A2(_0974_),
    .B1(_0762_),
    .B2(a_out[9]),
    .X(_0096_));
 sky130_fd_sc_hd__xnor2_2 _2097_ (.A(_0759_),
    .B(_0096_),
    .Y(_0097_));
 sky130_fd_sc_hd__xor2_2 _2098_ (.A(_0095_),
    .B(_0097_),
    .X(_0098_));
 sky130_fd_sc_hd__xor2_2 _2099_ (.A(_0094_),
    .B(_0098_),
    .X(_0099_));
 sky130_fd_sc_hd__xor2_2 _2100_ (.A(_0092_),
    .B(_0099_),
    .X(_0100_));
 sky130_fd_sc_hd__xnor2_2 _2101_ (.A(_0091_),
    .B(_0100_),
    .Y(_0101_));
 sky130_fd_sc_hd__nor2_2 _2102_ (.A(_1269_),
    .B(_1270_),
    .Y(_0102_));
 sky130_fd_sc_hd__o21ba_2 _2103_ (.A1(_1271_),
    .A2(_1280_),
    .B1_N(_0102_),
    .X(_0103_));
 sky130_fd_sc_hd__xnor2_2 _2104_ (.A(_0101_),
    .B(_0103_),
    .Y(_0104_));
 sky130_fd_sc_hd__a32o_2 _2105_ (.A1(_1227_),
    .A2(_1229_),
    .A3(_1279_),
    .B1(_1278_),
    .B2(_1274_),
    .X(_0105_));
 sky130_fd_sc_hd__xor2_2 _2106_ (.A(_0104_),
    .B(_0105_),
    .X(_0106_));
 sky130_fd_sc_hd__nor2_2 _2107_ (.A(_1281_),
    .B(_1283_),
    .Y(_0107_));
 sky130_fd_sc_hd__a21oi_2 _2108_ (.A1(_1260_),
    .A2(_1284_),
    .B1(_0107_),
    .Y(_0108_));
 sky130_fd_sc_hd__nor2_2 _2109_ (.A(_0106_),
    .B(_0108_),
    .Y(_0109_));
 sky130_fd_sc_hd__and2_2 _2110_ (.A(_0106_),
    .B(_0108_),
    .X(_0110_));
 sky130_fd_sc_hd__or2_4 _2111_ (.A(_0109_),
    .B(_0110_),
    .X(_0111_));
 sky130_fd_sc_hd__xor2_2 _2112_ (.A(_1299_),
    .B(_0111_),
    .X(_0112_));
 sky130_fd_sc_hd__nand2b_2 _2113_ (.A_N(_1258_),
    .B(_1286_),
    .Y(_0113_));
 sky130_fd_sc_hd__inv_2 _2114_ (.A(_1294_),
    .Y(_0114_));
 sky130_fd_sc_hd__or2_2 _2115_ (.A(_1299_),
    .B(_0111_),
    .X(_0115_));
 sky130_fd_sc_hd__nand2_2 _2116_ (.A(_1299_),
    .B(_0111_),
    .Y(_0116_));
 sky130_fd_sc_hd__nand2_2 _2117_ (.A(_0115_),
    .B(_0116_),
    .Y(_0117_));
 sky130_fd_sc_hd__o21ai_2 _2118_ (.A1(_0113_),
    .A2(_0117_),
    .B1(_0595_),
    .Y(_0118_));
 sky130_fd_sc_hd__a31o_2 _2119_ (.A1(_0113_),
    .A2(_0114_),
    .A3(_0117_),
    .B1(_0118_),
    .X(_0119_));
 sky130_fd_sc_hd__a21o_2 _2120_ (.A1(_1294_),
    .A2(_0112_),
    .B1(_0119_),
    .X(_0120_));
 sky130_fd_sc_hd__a21oi_2 _2121_ (.A1(_1298_),
    .A2(_0120_),
    .B1(reset),
    .Y(_0023_));
 sky130_fd_sc_hd__or2_2 _2122_ (.A(a_out[14]),
    .B(_0638_),
    .X(_0121_));
 sky130_fd_sc_hd__a21oi_2 _2123_ (.A1(_0679_),
    .A2(_0121_),
    .B1(\r2_mantissa[7] ),
    .Y(_0122_));
 sky130_fd_sc_hd__and4_2 _2124_ (.A(a_out[14]),
    .B(_0677_),
    .C(\r2_mantissa[8] ),
    .D(\r2_mantissa[7] ),
    .X(_0123_));
 sky130_fd_sc_hd__and4b_2 _2125_ (.A_N(_0123_),
    .B(\r2_mantissa[7] ),
    .C(_0679_),
    .D(_0121_),
    .X(_0124_));
 sky130_fd_sc_hd__nor2_2 _2126_ (.A(_0122_),
    .B(_0124_),
    .Y(_0125_));
 sky130_fd_sc_hd__a22o_2 _2127_ (.A1(a_out[13]),
    .A2(_0650_),
    .B1(_0654_),
    .B2(a_out[12]),
    .X(_0126_));
 sky130_fd_sc_hd__xnor2_2 _2128_ (.A(_0648_),
    .B(_0126_),
    .Y(_0127_));
 sky130_fd_sc_hd__xnor2_2 _2129_ (.A(_0125_),
    .B(_0127_),
    .Y(_0128_));
 sky130_fd_sc_hd__xor2_2 _2130_ (.A(_0088_),
    .B(_0128_),
    .X(_0129_));
 sky130_fd_sc_hd__nand2_2 _2131_ (.A(_0095_),
    .B(_0097_),
    .Y(_0130_));
 sky130_fd_sc_hd__and2_2 _2132_ (.A(\r2_mantissa[7] ),
    .B(_1301_),
    .X(_0131_));
 sky130_fd_sc_hd__a21o_2 _2133_ (.A1(_1302_),
    .A2(_0087_),
    .B1(_0131_),
    .X(_0132_));
 sky130_fd_sc_hd__a22o_2 _2134_ (.A1(a_out[9]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[8]),
    .X(_0133_));
 sky130_fd_sc_hd__a22o_2 _2135_ (.A1(a_out[11]),
    .A2(_0974_),
    .B1(_0763_),
    .B2(a_out[10]),
    .X(_0134_));
 sky130_fd_sc_hd__xnor2_2 _2136_ (.A(_0759_),
    .B(_0134_),
    .Y(_0135_));
 sky130_fd_sc_hd__xor2_2 _2137_ (.A(_0133_),
    .B(_0135_),
    .X(_0136_));
 sky130_fd_sc_hd__xor2_2 _2138_ (.A(_0132_),
    .B(_0136_),
    .X(_0137_));
 sky130_fd_sc_hd__xor2_2 _2139_ (.A(_0130_),
    .B(_0137_),
    .X(_0138_));
 sky130_fd_sc_hd__xor2_2 _2140_ (.A(_0129_),
    .B(_0138_),
    .X(_0139_));
 sky130_fd_sc_hd__o21ai_2 _2141_ (.A1(_0091_),
    .A2(_0100_),
    .B1(_0090_),
    .Y(_0140_));
 sky130_fd_sc_hd__xor2_2 _2142_ (.A(_0139_),
    .B(_0140_),
    .X(_0141_));
 sky130_fd_sc_hd__a32o_2 _2143_ (.A1(_1275_),
    .A2(_1277_),
    .A3(_0099_),
    .B1(_0098_),
    .B2(_0094_),
    .X(_0142_));
 sky130_fd_sc_hd__xor2_2 _2144_ (.A(_0141_),
    .B(_0142_),
    .X(_0143_));
 sky130_fd_sc_hd__nand2_2 _2145_ (.A(_0101_),
    .B(_0103_),
    .Y(_0144_));
 sky130_fd_sc_hd__nor2_2 _2146_ (.A(_0101_),
    .B(_0103_),
    .Y(_0145_));
 sky130_fd_sc_hd__a21o_2 _2147_ (.A1(_0144_),
    .A2(_0105_),
    .B1(_0145_),
    .X(_0146_));
 sky130_fd_sc_hd__xor2_2 _2148_ (.A(_0143_),
    .B(_0146_),
    .X(_0147_));
 sky130_fd_sc_hd__nand2_2 _2149_ (.A(_0109_),
    .B(_0147_),
    .Y(_0148_));
 sky130_fd_sc_hd__or2_2 _2150_ (.A(_0109_),
    .B(_0147_),
    .X(_0149_));
 sky130_fd_sc_hd__and2_2 _2151_ (.A(_0148_),
    .B(_0149_),
    .X(_0150_));
 sky130_fd_sc_hd__o21a_2 _2152_ (.A1(_0113_),
    .A2(_0117_),
    .B1(_0115_),
    .X(_0151_));
 sky130_fd_sc_hd__inv_2 _2153_ (.A(_0151_),
    .Y(_0152_));
 sky130_fd_sc_hd__a31o_2 _2154_ (.A1(_1287_),
    .A2(_1293_),
    .A3(_0112_),
    .B1(_0152_),
    .X(_0153_));
 sky130_fd_sc_hd__nor2_2 _2155_ (.A(_0150_),
    .B(_0153_),
    .Y(_0154_));
 sky130_fd_sc_hd__a21o_2 _2156_ (.A1(_0150_),
    .A2(_0153_),
    .B1(_1016_),
    .X(_0155_));
 sky130_fd_sc_hd__o2bb2a_2 _2157_ (.A1_N(_1020_),
    .A2_N(\r3_prod_mant[8] ),
    .B1(_0154_),
    .B2(_0155_),
    .X(_0156_));
 sky130_fd_sc_hd__nor2_2 _2158_ (.A(reset),
    .B(_0156_),
    .Y(_0024_));
 sky130_fd_sc_hd__buf_1 _2159_ (.A(_1020_),
    .X(_0157_));
 sky130_fd_sc_hd__nand2_2 _2160_ (.A(_0157_),
    .B(\r3_prod_mant[9] ),
    .Y(_0158_));
 sky130_fd_sc_hd__nand2_2 _2161_ (.A(_0143_),
    .B(_0146_),
    .Y(_0159_));
 sky130_fd_sc_hd__and2_2 _2162_ (.A(_0133_),
    .B(_0135_),
    .X(_0160_));
 sky130_fd_sc_hd__a21oi_2 _2163_ (.A1(_0125_),
    .A2(_0127_),
    .B1(_0122_),
    .Y(_0161_));
 sky130_fd_sc_hd__a22o_2 _2164_ (.A1(a_out[10]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[9]),
    .X(_0162_));
 sky130_fd_sc_hd__a22o_2 _2165_ (.A1(a_out[12]),
    .A2(_0974_),
    .B1(_0762_),
    .B2(a_out[11]),
    .X(_0163_));
 sky130_fd_sc_hd__xnor2_2 _2166_ (.A(_0759_),
    .B(_0163_),
    .Y(_0164_));
 sky130_fd_sc_hd__xor2_2 _2167_ (.A(_0162_),
    .B(_0164_),
    .X(_0165_));
 sky130_fd_sc_hd__xnor2_2 _2168_ (.A(_0161_),
    .B(_0165_),
    .Y(_0166_));
 sky130_fd_sc_hd__xnor2_2 _2169_ (.A(_0160_),
    .B(_0166_),
    .Y(_0167_));
 sky130_fd_sc_hd__a22o_2 _2170_ (.A1(a_out[14]),
    .A2(_0651_),
    .B1(_0655_),
    .B2(a_out[13]),
    .X(_0168_));
 sky130_fd_sc_hd__xnor2_2 _2171_ (.A(_0649_),
    .B(_0168_),
    .Y(_0169_));
 sky130_fd_sc_hd__nor2_2 _2172_ (.A(\r2_mantissa[9] ),
    .B(_0169_),
    .Y(_0170_));
 sky130_fd_sc_hd__and2_2 _2173_ (.A(\r2_mantissa[9] ),
    .B(_0169_),
    .X(_0171_));
 sky130_fd_sc_hd__nor2_2 _2174_ (.A(_0170_),
    .B(_0171_),
    .Y(_0172_));
 sky130_fd_sc_hd__xor2_2 _2175_ (.A(_0167_),
    .B(_0172_),
    .X(_0173_));
 sky130_fd_sc_hd__inv_2 _2176_ (.A(_0088_),
    .Y(_0174_));
 sky130_fd_sc_hd__nor2_2 _2177_ (.A(_0174_),
    .B(_0128_),
    .Y(_0175_));
 sky130_fd_sc_hd__o21ba_2 _2178_ (.A1(_0129_),
    .A2(_0138_),
    .B1_N(_0175_),
    .X(_0176_));
 sky130_fd_sc_hd__xor2_2 _2179_ (.A(_0173_),
    .B(_0176_),
    .X(_0177_));
 sky130_fd_sc_hd__a32o_2 _2180_ (.A1(_0095_),
    .A2(_0097_),
    .A3(_0137_),
    .B1(_0136_),
    .B2(_0132_),
    .X(_0178_));
 sky130_fd_sc_hd__xor2_2 _2181_ (.A(_0177_),
    .B(_0178_),
    .X(_0179_));
 sky130_fd_sc_hd__and2_2 _2182_ (.A(_0139_),
    .B(_0140_),
    .X(_0180_));
 sky130_fd_sc_hd__a21oi_2 _2183_ (.A1(_0141_),
    .A2(_0142_),
    .B1(_0180_),
    .Y(_0181_));
 sky130_fd_sc_hd__xnor2_2 _2184_ (.A(_0179_),
    .B(_0181_),
    .Y(_0182_));
 sky130_fd_sc_hd__nand2_2 _2185_ (.A(_0159_),
    .B(_0182_),
    .Y(_0183_));
 sky130_fd_sc_hd__or2_2 _2186_ (.A(_0159_),
    .B(_0182_),
    .X(_0184_));
 sky130_fd_sc_hd__nand2_2 _2187_ (.A(_0183_),
    .B(_0184_),
    .Y(_0185_));
 sky130_fd_sc_hd__a21boi_2 _2188_ (.A1(_0150_),
    .A2(_0153_),
    .B1_N(_0148_),
    .Y(_0186_));
 sky130_fd_sc_hd__o21ai_2 _2189_ (.A1(_0185_),
    .A2(_0186_),
    .B1(_0596_),
    .Y(_0187_));
 sky130_fd_sc_hd__a21o_2 _2190_ (.A1(_0185_),
    .A2(_0186_),
    .B1(_0187_),
    .X(_0188_));
 sky130_fd_sc_hd__a21oi_2 _2191_ (.A1(_0158_),
    .A2(_0188_),
    .B1(reset),
    .Y(_0025_));
 sky130_fd_sc_hd__nor2_2 _2192_ (.A(_0179_),
    .B(_0181_),
    .Y(_0189_));
 sky130_fd_sc_hd__and2b_2 _2193_ (.A_N(_0176_),
    .B(_0173_),
    .X(_0190_));
 sky130_fd_sc_hd__and2b_2 _2194_ (.A_N(_0177_),
    .B(_0178_),
    .X(_0191_));
 sky130_fd_sc_hd__nor2_2 _2195_ (.A(_0167_),
    .B(_0172_),
    .Y(_0192_));
 sky130_fd_sc_hd__or3b_2 _2196_ (.A(\r2_mantissa[10] ),
    .B(\r2_mantissa[9] ),
    .C_N(a_out[14]),
    .X(_0193_));
 sky130_fd_sc_hd__and3_2 _2197_ (.A(\r2_mantissa[11] ),
    .B(_0639_),
    .C(_0193_),
    .X(_0194_));
 sky130_fd_sc_hd__and2_2 _2198_ (.A(a_out[14]),
    .B(_0649_),
    .X(_0195_));
 sky130_fd_sc_hd__a221o_2 _2199_ (.A1(\r2_mantissa[10] ),
    .A2(_0195_),
    .B1(_0193_),
    .B2(\r2_mantissa[11] ),
    .C1(_0639_),
    .X(_0196_));
 sky130_fd_sc_hd__or2b_2 _2200_ (.A(_0194_),
    .B_N(_0196_),
    .X(_0197_));
 sky130_fd_sc_hd__and2_2 _2201_ (.A(_0162_),
    .B(_0164_),
    .X(_0198_));
 sky130_fd_sc_hd__a22o_2 _2202_ (.A1(a_out[11]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[10]),
    .X(_0199_));
 sky130_fd_sc_hd__a22o_2 _2203_ (.A1(a_out[13]),
    .A2(_0694_),
    .B1(_0763_),
    .B2(a_out[12]),
    .X(_0200_));
 sky130_fd_sc_hd__xnor2_2 _2204_ (.A(_0760_),
    .B(_0200_),
    .Y(_0201_));
 sky130_fd_sc_hd__xor2_2 _2205_ (.A(_0199_),
    .B(_0201_),
    .X(_0202_));
 sky130_fd_sc_hd__xnor2_2 _2206_ (.A(_0170_),
    .B(_0202_),
    .Y(_0203_));
 sky130_fd_sc_hd__xnor2_2 _2207_ (.A(_0198_),
    .B(_0203_),
    .Y(_0204_));
 sky130_fd_sc_hd__xor2_2 _2208_ (.A(_0197_),
    .B(_0204_),
    .X(_0205_));
 sky130_fd_sc_hd__nor2_2 _2209_ (.A(_0192_),
    .B(_0205_),
    .Y(_0206_));
 sky130_fd_sc_hd__and2_2 _2210_ (.A(_0192_),
    .B(_0205_),
    .X(_0207_));
 sky130_fd_sc_hd__nor2_2 _2211_ (.A(_0206_),
    .B(_0207_),
    .Y(_0208_));
 sky130_fd_sc_hd__and2b_2 _2212_ (.A_N(_0161_),
    .B(_0165_),
    .X(_0209_));
 sky130_fd_sc_hd__a21oi_2 _2213_ (.A1(_0160_),
    .A2(_0166_),
    .B1(_0209_),
    .Y(_0210_));
 sky130_fd_sc_hd__xnor2_2 _2214_ (.A(_0208_),
    .B(_0210_),
    .Y(_0211_));
 sky130_fd_sc_hd__o21ai_2 _2215_ (.A1(_0190_),
    .A2(_0191_),
    .B1(_0211_),
    .Y(_0212_));
 sky130_fd_sc_hd__or3_2 _2216_ (.A(_0190_),
    .B(_0191_),
    .C(_0211_),
    .X(_0213_));
 sky130_fd_sc_hd__and2_2 _2217_ (.A(_0212_),
    .B(_0213_),
    .X(_0214_));
 sky130_fd_sc_hd__nand2_2 _2218_ (.A(_0189_),
    .B(_0214_),
    .Y(_0215_));
 sky130_fd_sc_hd__or2_2 _2219_ (.A(_0189_),
    .B(_0214_),
    .X(_0216_));
 sky130_fd_sc_hd__nand2_2 _2220_ (.A(_0215_),
    .B(_0216_),
    .Y(_0217_));
 sky130_fd_sc_hd__and2_2 _2221_ (.A(_0183_),
    .B(_0184_),
    .X(_0218_));
 sky130_fd_sc_hd__nand4_2 _2222_ (.A(_1287_),
    .B(_0112_),
    .C(_0150_),
    .D(_0218_),
    .Y(_0219_));
 sky130_fd_sc_hd__a21o_2 _2223_ (.A1(_1290_),
    .A2(_1292_),
    .B1(_0219_),
    .X(_0220_));
 sky130_fd_sc_hd__o31a_2 _2224_ (.A1(_1121_),
    .A2(_1289_),
    .A3(_0219_),
    .B1(_0220_),
    .X(_0221_));
 sky130_fd_sc_hd__or3b_2 _2225_ (.A(_0151_),
    .B(_0185_),
    .C_N(_0150_),
    .X(_0222_));
 sky130_fd_sc_hd__or2_2 _2226_ (.A(_0148_),
    .B(_0182_),
    .X(_0223_));
 sky130_fd_sc_hd__and4_4 _2227_ (.A(_0184_),
    .B(_0221_),
    .C(_0222_),
    .D(_0223_),
    .X(_0224_));
 sky130_fd_sc_hd__xnor2_2 _2228_ (.A(_0217_),
    .B(_0224_),
    .Y(_0225_));
 sky130_fd_sc_hd__o2bb2a_2 _2229_ (.A1_N(_1020_),
    .A2_N(\r3_prod_mant[10] ),
    .B1(_1017_),
    .B2(_0225_),
    .X(_0226_));
 sky130_fd_sc_hd__nor2_2 _2230_ (.A(reset),
    .B(_0226_),
    .Y(_0026_));
 sky130_fd_sc_hd__nand2_2 _2231_ (.A(_1297_),
    .B(\r3_prod_mant[11] ),
    .Y(_0227_));
 sky130_fd_sc_hd__and2b_2 _2232_ (.A_N(_0210_),
    .B(_0208_),
    .X(_0228_));
 sky130_fd_sc_hd__or2_2 _2233_ (.A(_0197_),
    .B(_0204_),
    .X(_0229_));
 sky130_fd_sc_hd__and2_2 _2234_ (.A(_0199_),
    .B(_0201_),
    .X(_0230_));
 sky130_fd_sc_hd__a22o_2 _2235_ (.A1(a_out[12]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[11]),
    .X(_0231_));
 sky130_fd_sc_hd__a22o_2 _2236_ (.A1(a_out[14]),
    .A2(_0694_),
    .B1(_0763_),
    .B2(a_out[13]),
    .X(_0232_));
 sky130_fd_sc_hd__xnor2_2 _2237_ (.A(_0760_),
    .B(_0232_),
    .Y(_0233_));
 sky130_fd_sc_hd__xor2_2 _2238_ (.A(_0231_),
    .B(_0233_),
    .X(_0234_));
 sky130_fd_sc_hd__and2_2 _2239_ (.A(_0194_),
    .B(_0234_),
    .X(_0235_));
 sky130_fd_sc_hd__nor2_2 _2240_ (.A(_0194_),
    .B(_0234_),
    .Y(_0236_));
 sky130_fd_sc_hd__nor2_2 _2241_ (.A(_0235_),
    .B(_0236_),
    .Y(_0237_));
 sky130_fd_sc_hd__xnor2_2 _2242_ (.A(_0230_),
    .B(_0237_),
    .Y(_0238_));
 sky130_fd_sc_hd__xnor2_2 _2243_ (.A(_0649_),
    .B(_0238_),
    .Y(_0239_));
 sky130_fd_sc_hd__xnor2_2 _2244_ (.A(_0229_),
    .B(_0239_),
    .Y(_0240_));
 sky130_fd_sc_hd__and2b_2 _2245_ (.A_N(_0170_),
    .B(_0202_),
    .X(_0241_));
 sky130_fd_sc_hd__a21oi_2 _2246_ (.A1(_0198_),
    .A2(_0203_),
    .B1(_0241_),
    .Y(_0242_));
 sky130_fd_sc_hd__xnor2_2 _2247_ (.A(_0240_),
    .B(_0242_),
    .Y(_0243_));
 sky130_fd_sc_hd__o21a_2 _2248_ (.A1(_0207_),
    .A2(_0228_),
    .B1(_0243_),
    .X(_0244_));
 sky130_fd_sc_hd__nor3_2 _2249_ (.A(_0207_),
    .B(_0228_),
    .C(_0243_),
    .Y(_0245_));
 sky130_fd_sc_hd__or2_2 _2250_ (.A(_0244_),
    .B(_0245_),
    .X(_0246_));
 sky130_fd_sc_hd__xor2_2 _2251_ (.A(_0212_),
    .B(_0246_),
    .X(_0247_));
 sky130_fd_sc_hd__inv_4 _2252_ (.A(_0247_),
    .Y(_0248_));
 sky130_fd_sc_hd__o211a_2 _2253_ (.A1(_0217_),
    .A2(_0224_),
    .B1(_0248_),
    .C1(_0215_),
    .X(_0249_));
 sky130_fd_sc_hd__o21ai_2 _2254_ (.A1(_0215_),
    .A2(_0246_),
    .B1(_0596_),
    .Y(_0250_));
 sky130_fd_sc_hd__or2_2 _2255_ (.A(_0217_),
    .B(_0248_),
    .X(_0251_));
 sky130_fd_sc_hd__a41o_2 _2256_ (.A1(_0184_),
    .A2(_0221_),
    .A3(_0222_),
    .A4(_0223_),
    .B1(_0251_),
    .X(_0252_));
 sky130_fd_sc_hd__or3b_4 _2257_ (.A(_0249_),
    .B(_0250_),
    .C_N(_0252_),
    .X(_0253_));
 sky130_fd_sc_hd__a21oi_4 _2258_ (.A1(_0227_),
    .A2(_0253_),
    .B1(reset),
    .Y(_0027_));
 sky130_fd_sc_hd__nand2_2 _2259_ (.A(_1297_),
    .B(\r3_prod_mant[12] ),
    .Y(_0254_));
 sky130_fd_sc_hd__inv_2 _2260_ (.A(_0239_),
    .Y(_0255_));
 sky130_fd_sc_hd__or2b_2 _2261_ (.A(_0242_),
    .B_N(_0240_),
    .X(_0256_));
 sky130_fd_sc_hd__o21a_2 _2262_ (.A1(_0229_),
    .A2(_0255_),
    .B1(_0256_),
    .X(_0257_));
 sky130_fd_sc_hd__a21oi_2 _2263_ (.A1(_0230_),
    .A2(_0237_),
    .B1(_0235_),
    .Y(_0258_));
 sky130_fd_sc_hd__and2_2 _2264_ (.A(_0231_),
    .B(_0233_),
    .X(_0259_));
 sky130_fd_sc_hd__a22o_2 _2265_ (.A1(a_out[13]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[12]),
    .X(_0260_));
 sky130_fd_sc_hd__or3b_2 _2266_ (.A(\r2_mantissa[12] ),
    .B(\r2_mantissa[11] ),
    .C_N(a_out[14]),
    .X(_0261_));
 sky130_fd_sc_hd__a22o_2 _2267_ (.A1(a_out[14]),
    .A2(_0761_),
    .B1(_0261_),
    .B2(\r2_mantissa[13] ),
    .X(_0262_));
 sky130_fd_sc_hd__xor2_2 _2268_ (.A(_0260_),
    .B(_0262_),
    .X(_0263_));
 sky130_fd_sc_hd__nand2_2 _2269_ (.A(\r2_mantissa[11] ),
    .B(_0263_),
    .Y(_0264_));
 sky130_fd_sc_hd__or2_2 _2270_ (.A(\r2_mantissa[11] ),
    .B(_0263_),
    .X(_0265_));
 sky130_fd_sc_hd__nand2_2 _2271_ (.A(_0264_),
    .B(_0265_),
    .Y(_0266_));
 sky130_fd_sc_hd__xor2_2 _2272_ (.A(_0259_),
    .B(_0266_),
    .X(_0267_));
 sky130_fd_sc_hd__inv_2 _2273_ (.A(_0267_),
    .Y(_0268_));
 sky130_fd_sc_hd__nand2_2 _2274_ (.A(_0649_),
    .B(_0238_),
    .Y(_0269_));
 sky130_fd_sc_hd__xnor2_2 _2275_ (.A(_0268_),
    .B(_0269_),
    .Y(_0270_));
 sky130_fd_sc_hd__xnor2_2 _2276_ (.A(_0258_),
    .B(_0270_),
    .Y(_0271_));
 sky130_fd_sc_hd__nor2b_2 _2277_ (.A(_0257_),
    .B_N(_0271_),
    .Y(_0272_));
 sky130_fd_sc_hd__and2b_2 _2278_ (.A_N(_0271_),
    .B(_0257_),
    .X(_0273_));
 sky130_fd_sc_hd__nor2_2 _2279_ (.A(_0272_),
    .B(_0273_),
    .Y(_0274_));
 sky130_fd_sc_hd__nand2_2 _2280_ (.A(_0244_),
    .B(_0274_),
    .Y(_0275_));
 sky130_fd_sc_hd__or2_2 _2281_ (.A(_0244_),
    .B(_0274_),
    .X(_0276_));
 sky130_fd_sc_hd__nand2_2 _2282_ (.A(_0275_),
    .B(_0276_),
    .Y(_0277_));
 sky130_fd_sc_hd__a21o_2 _2283_ (.A1(_0212_),
    .A2(_0215_),
    .B1(_0246_),
    .X(_0278_));
 sky130_fd_sc_hd__and3_2 _2284_ (.A(_0252_),
    .B(_0277_),
    .C(_0278_),
    .X(_0279_));
 sky130_fd_sc_hd__a21o_2 _2285_ (.A1(_0252_),
    .A2(_0278_),
    .B1(_0277_),
    .X(_0280_));
 sky130_fd_sc_hd__or3b_4 _2286_ (.A(_0279_),
    .B(_1017_),
    .C_N(_0280_),
    .X(_0281_));
 sky130_fd_sc_hd__a21oi_4 _2287_ (.A1(_0254_),
    .A2(_0281_),
    .B1(reset),
    .Y(_0028_));
 sky130_fd_sc_hd__and2_2 _2288_ (.A(_1297_),
    .B(\r3_prod_mant[13] ),
    .X(_0282_));
 sky130_fd_sc_hd__and2_2 _2289_ (.A(_0244_),
    .B(_0274_),
    .X(_0283_));
 sky130_fd_sc_hd__a22o_2 _2290_ (.A1(a_out[14]),
    .A2(_0001_),
    .B1(_0000_),
    .B2(a_out[13]),
    .X(_0284_));
 sky130_fd_sc_hd__xnor2_2 _2291_ (.A(_0760_),
    .B(_0284_),
    .Y(_0285_));
 sky130_fd_sc_hd__nand3_2 _2292_ (.A(_0260_),
    .B(_0262_),
    .C(_0285_),
    .Y(_0286_));
 sky130_fd_sc_hd__a21o_2 _2293_ (.A1(_0260_),
    .A2(_0262_),
    .B1(_0285_),
    .X(_0287_));
 sky130_fd_sc_hd__nand2_2 _2294_ (.A(_0286_),
    .B(_0287_),
    .Y(_0288_));
 sky130_fd_sc_hd__or3b_2 _2295_ (.A(\r2_mantissa[11] ),
    .B(_0267_),
    .C_N(_0288_),
    .X(_0289_));
 sky130_fd_sc_hd__a21o_2 _2296_ (.A1(_0649_),
    .A2(_0268_),
    .B1(_0288_),
    .X(_0290_));
 sky130_fd_sc_hd__and2_2 _2297_ (.A(_0289_),
    .B(_0290_),
    .X(_0291_));
 sky130_fd_sc_hd__a21boi_2 _2298_ (.A1(_0259_),
    .A2(_0265_),
    .B1_N(_0264_),
    .Y(_0292_));
 sky130_fd_sc_hd__xnor2_2 _2299_ (.A(_0291_),
    .B(_0292_),
    .Y(_0293_));
 sky130_fd_sc_hd__or2b_2 _2300_ (.A(_0258_),
    .B_N(_0270_),
    .X(_0294_));
 sky130_fd_sc_hd__o31ai_2 _2301_ (.A1(\r2_mantissa[11] ),
    .A2(_0238_),
    .A3(_0268_),
    .B1(_0294_),
    .Y(_0295_));
 sky130_fd_sc_hd__xor2_2 _2302_ (.A(_0293_),
    .B(_0295_),
    .X(_0296_));
 sky130_fd_sc_hd__xnor2_2 _2303_ (.A(_0272_),
    .B(_0296_),
    .Y(_0297_));
 sky130_fd_sc_hd__a211oi_2 _2304_ (.A1(_0252_),
    .A2(_0278_),
    .B1(_0297_),
    .C1(_0277_),
    .Y(_0298_));
 sky130_fd_sc_hd__a311o_2 _2305_ (.A1(_0275_),
    .A2(_0280_),
    .A3(_0297_),
    .B1(_0298_),
    .C1(_1017_),
    .X(_0299_));
 sky130_fd_sc_hd__a21oi_2 _2306_ (.A1(_0283_),
    .A2(_0296_),
    .B1(_0299_),
    .Y(_0300_));
 sky130_fd_sc_hd__o21a_4 _2307_ (.A1(_0282_),
    .A2(_0300_),
    .B1(_0584_),
    .X(_0029_));
 sky130_fd_sc_hd__and2_2 _2308_ (.A(_1297_),
    .B(\r3_prod_mant[14] ),
    .X(_0301_));
 sky130_fd_sc_hd__o21a_2 _2309_ (.A1(_0272_),
    .A2(_0283_),
    .B1(_0296_),
    .X(_0302_));
 sky130_fd_sc_hd__nand2_2 _2310_ (.A(_0293_),
    .B(_0295_),
    .Y(_0303_));
 sky130_fd_sc_hd__or2b_2 _2311_ (.A(_0292_),
    .B_N(_0291_),
    .X(_0304_));
 sky130_fd_sc_hd__nand2_2 _2312_ (.A(_0289_),
    .B(_0304_),
    .Y(_0305_));
 sky130_fd_sc_hd__nand2_2 _2313_ (.A(a_out[14]),
    .B(_0000_),
    .Y(_0306_));
 sky130_fd_sc_hd__o21a_2 _2314_ (.A1(_0760_),
    .A2(_0284_),
    .B1(_0287_),
    .X(_0307_));
 sky130_fd_sc_hd__xnor2_2 _2315_ (.A(_0306_),
    .B(_0307_),
    .Y(_0308_));
 sky130_fd_sc_hd__xnor2_2 _2316_ (.A(_0305_),
    .B(_0308_),
    .Y(_0309_));
 sky130_fd_sc_hd__xnor2_2 _2317_ (.A(_0303_),
    .B(_0309_),
    .Y(_0310_));
 sky130_fd_sc_hd__o21ai_2 _2318_ (.A1(_0298_),
    .A2(_0302_),
    .B1(_0310_),
    .Y(_0311_));
 sky130_fd_sc_hd__o311a_2 _2319_ (.A1(_0298_),
    .A2(_0302_),
    .A3(_0310_),
    .B1(_0311_),
    .C1(_0596_),
    .X(_0312_));
 sky130_fd_sc_hd__o21a_2 _2320_ (.A1(_0301_),
    .A2(_0312_),
    .B1(_0584_),
    .X(_0030_));
 sky130_fd_sc_hd__nor2_2 _2321_ (.A(r2_sign),
    .B(s1_sign_a),
    .Y(_0313_));
 sky130_fd_sc_hd__and2_2 _2322_ (.A(r2_sign),
    .B(s1_sign_a),
    .X(_0314_));
 sky130_fd_sc_hd__inv_2 _2323_ (.A(r3_prod_sign),
    .Y(_0315_));
 sky130_fd_sc_hd__buf_1 _2324_ (.A(_0315_),
    .X(_0316_));
 sky130_fd_sc_hd__o32a_2 _2325_ (.A1(_1017_),
    .A2(_0313_),
    .A3(_0314_),
    .B1(_0316_),
    .B2(enable),
    .X(_0317_));
 sky130_fd_sc_hd__nor2_2 _2326_ (.A(reset),
    .B(_0317_),
    .Y(_0031_));
 sky130_fd_sc_hd__inv_2 _2327_ (.A(valid_s1),
    .Y(_0318_));
 sky130_fd_sc_hd__o22a_2 _2328_ (.A1(enable),
    .A2(_0318_),
    .B1(_0597_),
    .B2(_1017_),
    .X(_0319_));
 sky130_fd_sc_hd__nor2_2 _2329_ (.A(reset),
    .B(_0319_),
    .Y(_0032_));
 sky130_fd_sc_hd__o21ai_2 _2330_ (.A1(valid_s1),
    .A2(clear_acc),
    .B1(enable),
    .Y(_0320_));
 sky130_fd_sc_hd__buf_1 _2331_ (.A(_0320_),
    .X(_0321_));
 sky130_fd_sc_hd__nor2_2 _2332_ (.A(\r4_acc[0] ),
    .B(_0599_),
    .Y(_0322_));
 sky130_fd_sc_hd__and2_2 _2333_ (.A(\r4_acc[0] ),
    .B(_0599_),
    .X(_0323_));
 sky130_fd_sc_hd__o21ba_2 _2334_ (.A1(\r3_prod_mant[1] ),
    .A2(\r3_prod_mant[0] ),
    .B1_N(r3_prod_sign),
    .X(_0324_));
 sky130_fd_sc_hd__o41a_2 _2335_ (.A1(\r3_prod_mant[4] ),
    .A2(\r3_prod_mant[3] ),
    .A3(\r3_prod_mant[2] ),
    .A4(_0324_),
    .B1(_0315_),
    .X(_0325_));
 sky130_fd_sc_hd__or2_2 _2336_ (.A(\r3_prod_mant[5] ),
    .B(_0325_),
    .X(_0326_));
 sky130_fd_sc_hd__or3_2 _2337_ (.A(\r3_prod_mant[7] ),
    .B(\r3_prod_mant[6] ),
    .C(_0326_),
    .X(_0327_));
 sky130_fd_sc_hd__or3_2 _2338_ (.A(\r3_prod_mant[9] ),
    .B(\r3_prod_mant[8] ),
    .C(_0327_),
    .X(_0328_));
 sky130_fd_sc_hd__or2_2 _2339_ (.A(\r3_prod_mant[10] ),
    .B(_0328_),
    .X(_0329_));
 sky130_fd_sc_hd__or3_2 _2340_ (.A(\r3_prod_mant[12] ),
    .B(\r3_prod_mant[11] ),
    .C(_0329_),
    .X(_0330_));
 sky130_fd_sc_hd__o21a_2 _2341_ (.A1(\r3_prod_mant[13] ),
    .A2(_0330_),
    .B1(_0316_),
    .X(_0331_));
 sky130_fd_sc_hd__xnor2_2 _2342_ (.A(\r3_prod_mant[14] ),
    .B(_0331_),
    .Y(_0332_));
 sky130_fd_sc_hd__and2_2 _2343_ (.A(\r4_acc[14] ),
    .B(_0332_),
    .X(_0333_));
 sky130_fd_sc_hd__nor2_2 _2344_ (.A(\r4_acc[14] ),
    .B(_0332_),
    .Y(_0334_));
 sky130_fd_sc_hd__nor2_2 _2345_ (.A(_0333_),
    .B(_0334_),
    .Y(_0335_));
 sky130_fd_sc_hd__and2_2 _2346_ (.A(_0316_),
    .B(_0330_),
    .X(_0336_));
 sky130_fd_sc_hd__xnor2_2 _2347_ (.A(\r3_prod_mant[13] ),
    .B(_0336_),
    .Y(_0337_));
 sky130_fd_sc_hd__nand2_2 _2348_ (.A(\r4_acc[13] ),
    .B(_0337_),
    .Y(_0338_));
 sky130_fd_sc_hd__o21a_2 _2349_ (.A1(\r3_prod_mant[11] ),
    .A2(_0329_),
    .B1(_0316_),
    .X(_0339_));
 sky130_fd_sc_hd__xnor2_2 _2350_ (.A(\r3_prod_mant[12] ),
    .B(_0339_),
    .Y(_0340_));
 sky130_fd_sc_hd__and2_2 _2351_ (.A(_0316_),
    .B(_0329_),
    .X(_0341_));
 sky130_fd_sc_hd__xnor2_2 _2352_ (.A(\r3_prod_mant[11] ),
    .B(_0341_),
    .Y(_0342_));
 sky130_fd_sc_hd__nand2_2 _2353_ (.A(\r4_acc[11] ),
    .B(_0342_),
    .Y(_0343_));
 sky130_fd_sc_hd__and2_2 _2354_ (.A(_0316_),
    .B(_0328_),
    .X(_0344_));
 sky130_fd_sc_hd__xnor2_2 _2355_ (.A(\r3_prod_mant[10] ),
    .B(_0344_),
    .Y(_0345_));
 sky130_fd_sc_hd__and2_2 _2356_ (.A(\r4_acc[10] ),
    .B(_0345_),
    .X(_0346_));
 sky130_fd_sc_hd__o21a_2 _2357_ (.A1(\r3_prod_mant[8] ),
    .A2(_0327_),
    .B1(_0315_),
    .X(_0347_));
 sky130_fd_sc_hd__xnor2_2 _2358_ (.A(\r3_prod_mant[9] ),
    .B(_0347_),
    .Y(_0348_));
 sky130_fd_sc_hd__and2_2 _2359_ (.A(\r4_acc[9] ),
    .B(_0348_),
    .X(_0349_));
 sky130_fd_sc_hd__and2_2 _2360_ (.A(_0315_),
    .B(_0327_),
    .X(_0350_));
 sky130_fd_sc_hd__xnor2_2 _2361_ (.A(\r3_prod_mant[8] ),
    .B(_0350_),
    .Y(_0351_));
 sky130_fd_sc_hd__nand2_2 _2362_ (.A(\r4_acc[8] ),
    .B(_0351_),
    .Y(_0352_));
 sky130_fd_sc_hd__or2_2 _2363_ (.A(\r4_acc[8] ),
    .B(_0351_),
    .X(_0353_));
 sky130_fd_sc_hd__nand2_2 _2364_ (.A(_0352_),
    .B(_0353_),
    .Y(_0354_));
 sky130_fd_sc_hd__o21a_2 _2365_ (.A1(\r3_prod_mant[6] ),
    .A2(_0326_),
    .B1(_0315_),
    .X(_0355_));
 sky130_fd_sc_hd__xnor2_2 _2366_ (.A(\r3_prod_mant[7] ),
    .B(_0355_),
    .Y(_0356_));
 sky130_fd_sc_hd__or2_2 _2367_ (.A(\r4_acc[7] ),
    .B(_0356_),
    .X(_0357_));
 sky130_fd_sc_hd__and2_2 _2368_ (.A(_0315_),
    .B(_0326_),
    .X(_0358_));
 sky130_fd_sc_hd__xnor2_2 _2369_ (.A(\r3_prod_mant[6] ),
    .B(_0358_),
    .Y(_0359_));
 sky130_fd_sc_hd__xor2_2 _2370_ (.A(\r4_acc[6] ),
    .B(_0359_),
    .X(_0360_));
 sky130_fd_sc_hd__nand2_2 _2371_ (.A(\r3_prod_mant[5] ),
    .B(_0325_),
    .Y(_0361_));
 sky130_fd_sc_hd__and3b_2 _2372_ (.A_N(\r4_acc[5] ),
    .B(_0326_),
    .C(_0361_),
    .X(_0362_));
 sky130_fd_sc_hd__inv_2 _2373_ (.A(_0362_),
    .Y(_0363_));
 sky130_fd_sc_hd__inv_2 _2374_ (.A(\r3_prod_mant[4] ),
    .Y(_0364_));
 sky130_fd_sc_hd__o21a_2 _2375_ (.A1(\r3_prod_mant[2] ),
    .A2(_0324_),
    .B1(_0315_),
    .X(_0365_));
 sky130_fd_sc_hd__a21o_2 _2376_ (.A1(_0315_),
    .A2(\r3_prod_mant[3] ),
    .B1(_0365_),
    .X(_0366_));
 sky130_fd_sc_hd__xnor2_2 _2377_ (.A(_0364_),
    .B(_0366_),
    .Y(_0367_));
 sky130_fd_sc_hd__xnor2_2 _2378_ (.A(\r4_acc[4] ),
    .B(_0367_),
    .Y(_0368_));
 sky130_fd_sc_hd__xnor2_2 _2379_ (.A(\r3_prod_mant[3] ),
    .B(_0365_),
    .Y(_0369_));
 sky130_fd_sc_hd__nor2_2 _2380_ (.A(\r4_acc[3] ),
    .B(_0369_),
    .Y(_0370_));
 sky130_fd_sc_hd__inv_2 _2381_ (.A(_0370_),
    .Y(_0371_));
 sky130_fd_sc_hd__xnor2_2 _2382_ (.A(_1071_),
    .B(_0324_),
    .Y(_0372_));
 sky130_fd_sc_hd__and2b_2 _2383_ (.A_N(_0372_),
    .B(\r4_acc[2] ),
    .X(_0373_));
 sky130_fd_sc_hd__and2b_2 _2384_ (.A_N(\r4_acc[2] ),
    .B(_0372_),
    .X(_0374_));
 sky130_fd_sc_hd__nor2_2 _2385_ (.A(_0373_),
    .B(_0374_),
    .Y(_0375_));
 sky130_fd_sc_hd__and2b_2 _2386_ (.A_N(r3_prod_sign),
    .B(\r3_prod_mant[0] ),
    .X(_0376_));
 sky130_fd_sc_hd__xnor2_2 _2387_ (.A(\r3_prod_mant[1] ),
    .B(_0376_),
    .Y(_0377_));
 sky130_fd_sc_hd__nor2_2 _2388_ (.A(\r4_acc[1] ),
    .B(_0377_),
    .Y(_0378_));
 sky130_fd_sc_hd__nand2_2 _2389_ (.A(\r4_acc[1] ),
    .B(_0377_),
    .Y(_0379_));
 sky130_fd_sc_hd__o21ai_2 _2390_ (.A1(_0322_),
    .A2(_0378_),
    .B1(_0379_),
    .Y(_0380_));
 sky130_fd_sc_hd__and2_2 _2391_ (.A(\r4_acc[3] ),
    .B(_0369_),
    .X(_0381_));
 sky130_fd_sc_hd__a211o_2 _2392_ (.A1(_0375_),
    .A2(_0380_),
    .B1(_0381_),
    .C1(_0373_),
    .X(_0382_));
 sky130_fd_sc_hd__and2b_2 _2393_ (.A_N(_0367_),
    .B(\r4_acc[4] ),
    .X(_0383_));
 sky130_fd_sc_hd__a21boi_2 _2394_ (.A1(_0326_),
    .A2(_0361_),
    .B1_N(\r4_acc[5] ),
    .Y(_0384_));
 sky130_fd_sc_hd__a311o_2 _2395_ (.A1(_0368_),
    .A2(_0371_),
    .A3(_0382_),
    .B1(_0383_),
    .C1(_0384_),
    .X(_0385_));
 sky130_fd_sc_hd__a32o_2 _2396_ (.A1(_0360_),
    .A2(_0363_),
    .A3(_0385_),
    .B1(_0359_),
    .B2(\r4_acc[6] ),
    .X(_0386_));
 sky130_fd_sc_hd__nand2_2 _2397_ (.A(\r4_acc[7] ),
    .B(_0356_),
    .Y(_0387_));
 sky130_fd_sc_hd__a21boi_2 _2398_ (.A1(_0357_),
    .A2(_0386_),
    .B1_N(_0387_),
    .Y(_0388_));
 sky130_fd_sc_hd__or2_2 _2399_ (.A(_0354_),
    .B(_0388_),
    .X(_0389_));
 sky130_fd_sc_hd__nor2_2 _2400_ (.A(\r4_acc[9] ),
    .B(_0348_),
    .Y(_0390_));
 sky130_fd_sc_hd__or2_2 _2401_ (.A(_0349_),
    .B(_0390_),
    .X(_0391_));
 sky130_fd_sc_hd__a21oi_2 _2402_ (.A1(_0352_),
    .A2(_0389_),
    .B1(_0391_),
    .Y(_0392_));
 sky130_fd_sc_hd__nor2_2 _2403_ (.A(\r4_acc[10] ),
    .B(_0345_),
    .Y(_0393_));
 sky130_fd_sc_hd__or2_2 _2404_ (.A(_0346_),
    .B(_0393_),
    .X(_0394_));
 sky130_fd_sc_hd__o21ba_2 _2405_ (.A1(_0349_),
    .A2(_0392_),
    .B1_N(_0394_),
    .X(_0395_));
 sky130_fd_sc_hd__or2_2 _2406_ (.A(\r4_acc[11] ),
    .B(_0342_),
    .X(_0396_));
 sky130_fd_sc_hd__nand2_2 _2407_ (.A(_0343_),
    .B(_0396_),
    .Y(_0397_));
 sky130_fd_sc_hd__o21bai_2 _2408_ (.A1(_0346_),
    .A2(_0395_),
    .B1_N(_0397_),
    .Y(_0398_));
 sky130_fd_sc_hd__xnor2_2 _2409_ (.A(\r4_acc[12] ),
    .B(_0340_),
    .Y(_0399_));
 sky130_fd_sc_hd__a21oi_2 _2410_ (.A1(_0343_),
    .A2(_0398_),
    .B1(_0399_),
    .Y(_0400_));
 sky130_fd_sc_hd__a21oi_2 _2411_ (.A1(\r4_acc[12] ),
    .A2(_0340_),
    .B1(_0400_),
    .Y(_0401_));
 sky130_fd_sc_hd__nor2_2 _2412_ (.A(\r4_acc[13] ),
    .B(_0337_),
    .Y(_0402_));
 sky130_fd_sc_hd__a21oi_2 _2413_ (.A1(_0338_),
    .A2(_0401_),
    .B1(_0402_),
    .Y(_0403_));
 sky130_fd_sc_hd__a21oi_2 _2414_ (.A1(_0335_),
    .A2(_0403_),
    .B1(_0333_),
    .Y(_0404_));
 sky130_fd_sc_hd__inv_2 _2415_ (.A(\r4_acc[15] ),
    .Y(_0405_));
 sky130_fd_sc_hd__a211o_2 _2416_ (.A1(_0316_),
    .A2(\r3_prod_mant[14] ),
    .B1(_0331_),
    .C1(_0405_),
    .X(_0406_));
 sky130_fd_sc_hd__nor2b_2 _2417_ (.A(_0404_),
    .B_N(_0406_),
    .Y(_0407_));
 sky130_fd_sc_hd__nor2_2 _2418_ (.A(_0346_),
    .B(_0395_),
    .Y(_0408_));
 sky130_fd_sc_hd__xnor2_2 _2419_ (.A(_0397_),
    .B(_0408_),
    .Y(_0409_));
 sky130_fd_sc_hd__nor2_2 _2420_ (.A(_0349_),
    .B(_0392_),
    .Y(_0410_));
 sky130_fd_sc_hd__xnor2_2 _2421_ (.A(_0394_),
    .B(_0410_),
    .Y(_0411_));
 sky130_fd_sc_hd__nand2_2 _2422_ (.A(_0357_),
    .B(_0387_),
    .Y(_0412_));
 sky130_fd_sc_hd__nor2_2 _2423_ (.A(_0384_),
    .B(_0362_),
    .Y(_0413_));
 sky130_fd_sc_hd__nor2_2 _2424_ (.A(_0322_),
    .B(_0323_),
    .Y(_0414_));
 sky130_fd_sc_hd__and2_2 _2425_ (.A(\r4_acc[1] ),
    .B(_0377_),
    .X(_0415_));
 sky130_fd_sc_hd__nor2_2 _2426_ (.A(_0415_),
    .B(_0378_),
    .Y(_0416_));
 sky130_fd_sc_hd__nor2_2 _2427_ (.A(_0381_),
    .B(_0370_),
    .Y(_0417_));
 sky130_fd_sc_hd__and4_2 _2428_ (.A(_0414_),
    .B(_0368_),
    .C(_0416_),
    .D(_0417_),
    .X(_0418_));
 sky130_fd_sc_hd__and4_2 _2429_ (.A(_0360_),
    .B(_0375_),
    .C(_0413_),
    .D(_0418_),
    .X(_0419_));
 sky130_fd_sc_hd__or3b_2 _2430_ (.A(_0399_),
    .B(_0412_),
    .C_N(_0419_),
    .X(_0420_));
 sky130_fd_sc_hd__nand2_2 _2431_ (.A(_0354_),
    .B(_0388_),
    .Y(_0421_));
 sky130_fd_sc_hd__and2_2 _2432_ (.A(_0389_),
    .B(_0421_),
    .X(_0422_));
 sky130_fd_sc_hd__o211ai_2 _2433_ (.A1(\r3_prod_mant[14] ),
    .A2(_0331_),
    .B1(_0405_),
    .C1(_0316_),
    .Y(_0423_));
 sky130_fd_sc_hd__inv_2 _2434_ (.A(_0338_),
    .Y(_0424_));
 sky130_fd_sc_hd__nor2_2 _2435_ (.A(_0424_),
    .B(_0402_),
    .Y(_0425_));
 sky130_fd_sc_hd__and4bb_2 _2436_ (.A_N(_0420_),
    .B_N(_0422_),
    .C(_0423_),
    .D(_0425_),
    .X(_0426_));
 sky130_fd_sc_hd__and3_2 _2437_ (.A(_0391_),
    .B(_0352_),
    .C(_0389_),
    .X(_0427_));
 sky130_fd_sc_hd__or2_2 _2438_ (.A(_0392_),
    .B(_0427_),
    .X(_0428_));
 sky130_fd_sc_hd__nand4_2 _2439_ (.A(_0409_),
    .B(_0411_),
    .C(_0426_),
    .D(_0428_),
    .Y(_0429_));
 sky130_fd_sc_hd__xor2_2 _2440_ (.A(_0335_),
    .B(_0403_),
    .X(_0430_));
 sky130_fd_sc_hd__mux2_2 _2441_ (.A0(_0423_),
    .A1(_0406_),
    .S(_0404_),
    .X(_0431_));
 sky130_fd_sc_hd__o31ai_2 _2442_ (.A1(_0407_),
    .A2(_0429_),
    .A3(_0430_),
    .B1(_0431_),
    .Y(_0432_));
 sky130_fd_sc_hd__buf_1 _2443_ (.A(_0432_),
    .X(_0433_));
 sky130_fd_sc_hd__o311a_2 _2444_ (.A1(_0322_),
    .A2(_0323_),
    .A3(_0433_),
    .B1(_0596_),
    .C1(valid_s1),
    .X(_0434_));
 sky130_fd_sc_hd__a21oi_2 _2445_ (.A1(\r4_acc[0] ),
    .A2(_0321_),
    .B1(_0434_),
    .Y(_0435_));
 sky130_fd_sc_hd__nor2_2 _2446_ (.A(reset),
    .B(_0435_),
    .Y(_0033_));
 sky130_fd_sc_hd__buf_1 _2447_ (.A(_0432_),
    .X(_0436_));
 sky130_fd_sc_hd__inv_2 _2448_ (.A(_0423_),
    .Y(_0437_));
 sky130_fd_sc_hd__nor2_2 _2449_ (.A(_0437_),
    .B(_0407_),
    .Y(_0438_));
 sky130_fd_sc_hd__a211oi_2 _2450_ (.A1(_0436_),
    .A2(_0438_),
    .B1(_0318_),
    .C1(_1016_),
    .Y(_0439_));
 sky130_fd_sc_hd__buf_1 _2451_ (.A(_0439_),
    .X(_0440_));
 sky130_fd_sc_hd__xnor2_2 _2452_ (.A(_0322_),
    .B(_0416_),
    .Y(_0441_));
 sky130_fd_sc_hd__or2_2 _2453_ (.A(_0436_),
    .B(_0441_),
    .X(_0442_));
 sky130_fd_sc_hd__a22o_2 _2454_ (.A1(\r4_acc[1] ),
    .A2(_0321_),
    .B1(_0440_),
    .B2(_0442_),
    .X(_0443_));
 sky130_fd_sc_hd__and2_2 _2455_ (.A(_0578_),
    .B(_0443_),
    .X(_0444_));
 sky130_fd_sc_hd__buf_2 _2456_ (.A(_0444_),
    .X(_0034_));
 sky130_fd_sc_hd__buf_1 _2457_ (.A(_0577_),
    .X(_0445_));
 sky130_fd_sc_hd__buf_1 _2458_ (.A(_0320_),
    .X(_0446_));
 sky130_fd_sc_hd__nand2_2 _2459_ (.A(_0375_),
    .B(_0380_),
    .Y(_0447_));
 sky130_fd_sc_hd__or2_2 _2460_ (.A(_0375_),
    .B(_0380_),
    .X(_0448_));
 sky130_fd_sc_hd__a21o_2 _2461_ (.A1(_0447_),
    .A2(_0448_),
    .B1(_0433_),
    .X(_0449_));
 sky130_fd_sc_hd__a22o_2 _2462_ (.A1(\r4_acc[2] ),
    .A2(_0446_),
    .B1(_0440_),
    .B2(_0449_),
    .X(_0450_));
 sky130_fd_sc_hd__and2_2 _2463_ (.A(_0445_),
    .B(_0450_),
    .X(_0451_));
 sky130_fd_sc_hd__buf_2 _2464_ (.A(_0451_),
    .X(_0035_));
 sky130_fd_sc_hd__a21oi_2 _2465_ (.A1(_0375_),
    .A2(_0380_),
    .B1(_0373_),
    .Y(_0452_));
 sky130_fd_sc_hd__and2_2 _2466_ (.A(_0452_),
    .B(_0417_),
    .X(_0453_));
 sky130_fd_sc_hd__nor2_2 _2467_ (.A(_0452_),
    .B(_0417_),
    .Y(_0454_));
 sky130_fd_sc_hd__or3_2 _2468_ (.A(_0436_),
    .B(_0453_),
    .C(_0454_),
    .X(_0455_));
 sky130_fd_sc_hd__a22o_2 _2469_ (.A1(\r4_acc[3] ),
    .A2(_0321_),
    .B1(_0440_),
    .B2(_0455_),
    .X(_0456_));
 sky130_fd_sc_hd__and2_2 _2470_ (.A(_0445_),
    .B(_0456_),
    .X(_0457_));
 sky130_fd_sc_hd__buf_2 _2471_ (.A(_0457_),
    .X(_0036_));
 sky130_fd_sc_hd__and3_2 _2472_ (.A(_0368_),
    .B(_0371_),
    .C(_0382_),
    .X(_0458_));
 sky130_fd_sc_hd__a21oi_2 _2473_ (.A1(_0371_),
    .A2(_0382_),
    .B1(_0368_),
    .Y(_0459_));
 sky130_fd_sc_hd__o21bai_2 _2474_ (.A1(_0458_),
    .A2(_0459_),
    .B1_N(_0433_),
    .Y(_0460_));
 sky130_fd_sc_hd__a22o_2 _2475_ (.A1(\r4_acc[4] ),
    .A2(_0321_),
    .B1(_0440_),
    .B2(_0460_),
    .X(_0461_));
 sky130_fd_sc_hd__and2_2 _2476_ (.A(_0445_),
    .B(_0461_),
    .X(_0462_));
 sky130_fd_sc_hd__buf_2 _2477_ (.A(_0462_),
    .X(_0037_));
 sky130_fd_sc_hd__nor2_2 _2478_ (.A(_0383_),
    .B(_0458_),
    .Y(_0463_));
 sky130_fd_sc_hd__nor2_2 _2479_ (.A(_0463_),
    .B(_0413_),
    .Y(_0464_));
 sky130_fd_sc_hd__nand2_2 _2480_ (.A(_0463_),
    .B(_0413_),
    .Y(_0465_));
 sky130_fd_sc_hd__or3b_2 _2481_ (.A(_0464_),
    .B(_0436_),
    .C_N(_0465_),
    .X(_0466_));
 sky130_fd_sc_hd__a22o_2 _2482_ (.A1(\r4_acc[5] ),
    .A2(_0321_),
    .B1(_0440_),
    .B2(_0466_),
    .X(_0467_));
 sky130_fd_sc_hd__and2_2 _2483_ (.A(_0445_),
    .B(_0467_),
    .X(_0468_));
 sky130_fd_sc_hd__buf_2 _2484_ (.A(_0468_),
    .X(_0038_));
 sky130_fd_sc_hd__nand2_2 _2485_ (.A(_0363_),
    .B(_0385_),
    .Y(_0469_));
 sky130_fd_sc_hd__xnor2_2 _2486_ (.A(_0360_),
    .B(_0469_),
    .Y(_0470_));
 sky130_fd_sc_hd__or2_2 _2487_ (.A(_0433_),
    .B(_0470_),
    .X(_0471_));
 sky130_fd_sc_hd__a22o_2 _2488_ (.A1(\r4_acc[6] ),
    .A2(_0321_),
    .B1(_0440_),
    .B2(_0471_),
    .X(_0472_));
 sky130_fd_sc_hd__and2_2 _2489_ (.A(_0445_),
    .B(_0472_),
    .X(_0473_));
 sky130_fd_sc_hd__buf_2 _2490_ (.A(_0473_),
    .X(_0039_));
 sky130_fd_sc_hd__xnor2_2 _2491_ (.A(_0386_),
    .B(_0412_),
    .Y(_0474_));
 sky130_fd_sc_hd__or2_2 _2492_ (.A(_0436_),
    .B(_0474_),
    .X(_0475_));
 sky130_fd_sc_hd__a22o_2 _2493_ (.A1(\r4_acc[7] ),
    .A2(_0321_),
    .B1(_0440_),
    .B2(_0475_),
    .X(_0476_));
 sky130_fd_sc_hd__and2_2 _2494_ (.A(_0578_),
    .B(_0476_),
    .X(_0477_));
 sky130_fd_sc_hd__buf_2 _2495_ (.A(_0477_),
    .X(_0040_));
 sky130_fd_sc_hd__or2_2 _2496_ (.A(_0422_),
    .B(_0436_),
    .X(_0478_));
 sky130_fd_sc_hd__a22o_2 _2497_ (.A1(\r4_acc[8] ),
    .A2(_0446_),
    .B1(_0439_),
    .B2(_0478_),
    .X(_0479_));
 sky130_fd_sc_hd__and2_2 _2498_ (.A(_0445_),
    .B(_0479_),
    .X(_0480_));
 sky130_fd_sc_hd__buf_1 _2499_ (.A(_0480_),
    .X(_0041_));
 sky130_fd_sc_hd__or2b_2 _2500_ (.A(_0433_),
    .B_N(_0428_),
    .X(_0481_));
 sky130_fd_sc_hd__a22o_2 _2501_ (.A1(\r4_acc[9] ),
    .A2(_0446_),
    .B1(_0439_),
    .B2(_0481_),
    .X(_0482_));
 sky130_fd_sc_hd__and2_2 _2502_ (.A(_0445_),
    .B(_0482_),
    .X(_0483_));
 sky130_fd_sc_hd__buf_1 _2503_ (.A(_0483_),
    .X(_0042_));
 sky130_fd_sc_hd__or2b_2 _2504_ (.A(_0433_),
    .B_N(_0411_),
    .X(_0484_));
 sky130_fd_sc_hd__a22o_2 _2505_ (.A1(\r4_acc[10] ),
    .A2(_0446_),
    .B1(_0439_),
    .B2(_0484_),
    .X(_0485_));
 sky130_fd_sc_hd__and2_2 _2506_ (.A(_1172_),
    .B(_0485_),
    .X(_0486_));
 sky130_fd_sc_hd__buf_1 _2507_ (.A(_0486_),
    .X(_0043_));
 sky130_fd_sc_hd__or2b_2 _2508_ (.A(_0433_),
    .B_N(_0409_),
    .X(_0487_));
 sky130_fd_sc_hd__a22o_2 _2509_ (.A1(\r4_acc[11] ),
    .A2(_0446_),
    .B1(_0439_),
    .B2(_0487_),
    .X(_0488_));
 sky130_fd_sc_hd__and2_2 _2510_ (.A(_1172_),
    .B(_0488_),
    .X(_0489_));
 sky130_fd_sc_hd__buf_1 _2511_ (.A(_0489_),
    .X(_0044_));
 sky130_fd_sc_hd__and3_2 _2512_ (.A(_0399_),
    .B(_0343_),
    .C(_0398_),
    .X(_0490_));
 sky130_fd_sc_hd__o21bai_2 _2513_ (.A1(_0400_),
    .A2(_0490_),
    .B1_N(_0433_),
    .Y(_0491_));
 sky130_fd_sc_hd__a22o_2 _2514_ (.A1(\r4_acc[12] ),
    .A2(_0446_),
    .B1(_0439_),
    .B2(_0491_),
    .X(_0492_));
 sky130_fd_sc_hd__and2_2 _2515_ (.A(_1172_),
    .B(_0492_),
    .X(_0493_));
 sky130_fd_sc_hd__buf_1 _2516_ (.A(_0493_),
    .X(_0045_));
 sky130_fd_sc_hd__and2_2 _2517_ (.A(_0401_),
    .B(_0425_),
    .X(_0494_));
 sky130_fd_sc_hd__nor2_2 _2518_ (.A(_0401_),
    .B(_0425_),
    .Y(_0495_));
 sky130_fd_sc_hd__or3_2 _2519_ (.A(_0436_),
    .B(_0494_),
    .C(_0495_),
    .X(_0496_));
 sky130_fd_sc_hd__a22o_2 _2520_ (.A1(\r4_acc[13] ),
    .A2(_0446_),
    .B1(_0439_),
    .B2(_0496_),
    .X(_0497_));
 sky130_fd_sc_hd__and2_2 _2521_ (.A(_1172_),
    .B(_0497_),
    .X(_0498_));
 sky130_fd_sc_hd__buf_1 _2522_ (.A(_0498_),
    .X(_0046_));
 sky130_fd_sc_hd__or2_2 _2523_ (.A(_0430_),
    .B(_0436_),
    .X(_0499_));
 sky130_fd_sc_hd__a22o_2 _2524_ (.A1(\r4_acc[14] ),
    .A2(_0446_),
    .B1(_0440_),
    .B2(_0499_),
    .X(_0500_));
 sky130_fd_sc_hd__and2_2 _2525_ (.A(_1172_),
    .B(_0500_),
    .X(_0501_));
 sky130_fd_sc_hd__buf_2 _2526_ (.A(_0501_),
    .X(_0047_));
 sky130_fd_sc_hd__a32o_2 _2527_ (.A1(valid_s1),
    .A2(_0595_),
    .A3(_0438_),
    .B1(_0321_),
    .B2(\r4_acc[15] ),
    .X(_0502_));
 sky130_fd_sc_hd__and2_2 _2528_ (.A(_0445_),
    .B(_0502_),
    .X(_0503_));
 sky130_fd_sc_hd__buf_1 _2529_ (.A(_0503_),
    .X(_0048_));
 sky130_fd_sc_hd__buf_1 _2530_ (.A(_1297_),
    .X(_0504_));
 sky130_fd_sc_hd__buf_1 _2531_ (.A(_0578_),
    .X(_0505_));
 sky130_fd_sc_hd__or2_2 _2532_ (.A(enable),
    .B(a_out[0]),
    .X(_0506_));
 sky130_fd_sc_hd__o211a_2 _2533_ (.A1(_0504_),
    .A2(a_in[0]),
    .B1(_0505_),
    .C1(_0506_),
    .X(_0049_));
 sky130_fd_sc_hd__or2_2 _2534_ (.A(enable),
    .B(a_out[1]),
    .X(_0507_));
 sky130_fd_sc_hd__o211a_2 _2535_ (.A1(_0157_),
    .A2(a_in[1]),
    .B1(_0505_),
    .C1(_0507_),
    .X(_0050_));
 sky130_fd_sc_hd__buf_1 _2536_ (.A(_1297_),
    .X(_0508_));
 sky130_fd_sc_hd__buf_1 _2537_ (.A(_0578_),
    .X(_0509_));
 sky130_fd_sc_hd__or2_2 _2538_ (.A(enable),
    .B(a_out[2]),
    .X(_0510_));
 sky130_fd_sc_hd__o211a_2 _2539_ (.A1(_0508_),
    .A2(a_in[2]),
    .B1(_0509_),
    .C1(_0510_),
    .X(_0051_));
 sky130_fd_sc_hd__buf_1 _2540_ (.A(_0578_),
    .X(_0511_));
 sky130_fd_sc_hd__or2_2 _2541_ (.A(enable),
    .B(a_out[3]),
    .X(_0512_));
 sky130_fd_sc_hd__o211a_2 _2542_ (.A1(_0508_),
    .A2(a_in[3]),
    .B1(_0511_),
    .C1(_0512_),
    .X(_0052_));
 sky130_fd_sc_hd__or2_2 _2543_ (.A(enable),
    .B(a_out[4]),
    .X(_0513_));
 sky130_fd_sc_hd__o211a_2 _2544_ (.A1(_0508_),
    .A2(a_in[4]),
    .B1(_0511_),
    .C1(_0513_),
    .X(_0053_));
 sky130_fd_sc_hd__or2_2 _2545_ (.A(enable),
    .B(a_out[5]),
    .X(_0514_));
 sky130_fd_sc_hd__o211a_2 _2546_ (.A1(_0508_),
    .A2(a_in[5]),
    .B1(_0511_),
    .C1(_0514_),
    .X(_0054_));
 sky130_fd_sc_hd__or2_2 _2547_ (.A(enable),
    .B(a_out[6]),
    .X(_0515_));
 sky130_fd_sc_hd__o211a_2 _2548_ (.A1(_0508_),
    .A2(a_in[6]),
    .B1(_0511_),
    .C1(_0515_),
    .X(_0055_));
 sky130_fd_sc_hd__or2_2 _2549_ (.A(enable),
    .B(a_out[7]),
    .X(_0516_));
 sky130_fd_sc_hd__o211a_2 _2550_ (.A1(_0508_),
    .A2(a_in[7]),
    .B1(_0511_),
    .C1(_0516_),
    .X(_0056_));
 sky130_fd_sc_hd__or2_2 _2551_ (.A(enable),
    .B(a_out[8]),
    .X(_0517_));
 sky130_fd_sc_hd__o211a_2 _2552_ (.A1(_0508_),
    .A2(a_in[8]),
    .B1(_0511_),
    .C1(_0517_),
    .X(_0057_));
 sky130_fd_sc_hd__or2_2 _2553_ (.A(enable),
    .B(a_out[9]),
    .X(_0518_));
 sky130_fd_sc_hd__o211a_2 _2554_ (.A1(_0508_),
    .A2(a_in[9]),
    .B1(_0511_),
    .C1(_0518_),
    .X(_0058_));
 sky130_fd_sc_hd__or2_2 _2555_ (.A(enable),
    .B(a_out[10]),
    .X(_0519_));
 sky130_fd_sc_hd__o211a_2 _2556_ (.A1(_0157_),
    .A2(a_in[10]),
    .B1(_0511_),
    .C1(_0519_),
    .X(_0059_));
 sky130_fd_sc_hd__or2_2 _2557_ (.A(enable),
    .B(a_out[11]),
    .X(_0520_));
 sky130_fd_sc_hd__o211a_2 _2558_ (.A1(_0157_),
    .A2(a_in[11]),
    .B1(_0509_),
    .C1(_0520_),
    .X(_0060_));
 sky130_fd_sc_hd__or2_2 _2559_ (.A(enable),
    .B(a_out[12]),
    .X(_0521_));
 sky130_fd_sc_hd__o211a_2 _2560_ (.A1(_0157_),
    .A2(a_in[12]),
    .B1(_1172_),
    .C1(_0521_),
    .X(_0061_));
 sky130_fd_sc_hd__or2_2 _2561_ (.A(enable),
    .B(a_out[13]),
    .X(_0522_));
 sky130_fd_sc_hd__o211a_2 _2562_ (.A1(_0157_),
    .A2(a_in[13]),
    .B1(_0509_),
    .C1(_0522_),
    .X(_0062_));
 sky130_fd_sc_hd__or2_2 _2563_ (.A(enable),
    .B(a_out[14]),
    .X(_0523_));
 sky130_fd_sc_hd__o211a_2 _2564_ (.A1(_0157_),
    .A2(a_in[14]),
    .B1(_0586_),
    .C1(_0523_),
    .X(_0063_));
 sky130_fd_sc_hd__buf_1 _2565_ (.A(_1297_),
    .X(_0524_));
 sky130_fd_sc_hd__or4_2 _2566_ (.A(a_in[9]),
    .B(a_in[8]),
    .C(a_in[11]),
    .D(a_in[10]),
    .X(_0525_));
 sky130_fd_sc_hd__or4_2 _2567_ (.A(a_in[13]),
    .B(a_in[12]),
    .C(a_in[14]),
    .D(_0525_),
    .X(_0526_));
 sky130_fd_sc_hd__or4_2 _2568_ (.A(a_in[1]),
    .B(a_in[0]),
    .C(a_in[3]),
    .D(a_in[2]),
    .X(_0527_));
 sky130_fd_sc_hd__or4_2 _2569_ (.A(a_in[5]),
    .B(a_in[4]),
    .C(a_in[7]),
    .D(a_in[6]),
    .X(_0528_));
 sky130_fd_sc_hd__o31a_2 _2570_ (.A1(_0526_),
    .A2(_0527_),
    .A3(_0528_),
    .B1(a_in[15]),
    .X(_0529_));
 sky130_fd_sc_hd__or2_2 _2571_ (.A(enable),
    .B(s1_sign_a),
    .X(_0530_));
 sky130_fd_sc_hd__o211a_2 _2572_ (.A1(_0524_),
    .A2(_0529_),
    .B1(_0530_),
    .C1(_0584_),
    .X(_0064_));
 sky130_fd_sc_hd__or2_2 _2573_ (.A(enable),
    .B(b_out[0]),
    .X(_0531_));
 sky130_fd_sc_hd__o211a_2 _2574_ (.A1(_0504_),
    .A2(b_in[0]),
    .B1(_0509_),
    .C1(_0531_),
    .X(_0065_));
 sky130_fd_sc_hd__or2_2 _2575_ (.A(enable),
    .B(b_out[1]),
    .X(_0532_));
 sky130_fd_sc_hd__o211a_2 _2576_ (.A1(_0504_),
    .A2(b_in[1]),
    .B1(_0505_),
    .C1(_0532_),
    .X(_0066_));
 sky130_fd_sc_hd__or2_2 _2577_ (.A(enable),
    .B(b_out[2]),
    .X(_0533_));
 sky130_fd_sc_hd__o211a_2 _2578_ (.A1(_0504_),
    .A2(b_in[2]),
    .B1(_0586_),
    .C1(_0533_),
    .X(_0067_));
 sky130_fd_sc_hd__or2_2 _2579_ (.A(enable),
    .B(b_out[3]),
    .X(_0534_));
 sky130_fd_sc_hd__o211a_2 _2580_ (.A1(_0504_),
    .A2(b_in[3]),
    .B1(_0586_),
    .C1(_0534_),
    .X(_0068_));
 sky130_fd_sc_hd__or2_2 _2581_ (.A(enable),
    .B(b_out[4]),
    .X(_0535_));
 sky130_fd_sc_hd__o211a_2 _2582_ (.A1(_0504_),
    .A2(b_in[4]),
    .B1(_0509_),
    .C1(_0535_),
    .X(_0069_));
 sky130_fd_sc_hd__or2_2 _2583_ (.A(enable),
    .B(b_out[5]),
    .X(_0536_));
 sky130_fd_sc_hd__o211a_2 _2584_ (.A1(_0504_),
    .A2(b_in[5]),
    .B1(_0505_),
    .C1(_0536_),
    .X(_0070_));
 sky130_fd_sc_hd__or2_2 _2585_ (.A(enable),
    .B(b_out[6]),
    .X(_0537_));
 sky130_fd_sc_hd__o211a_2 _2586_ (.A1(_0504_),
    .A2(b_in[6]),
    .B1(_0505_),
    .C1(_0537_),
    .X(_0071_));
 sky130_fd_sc_hd__or2_2 _2587_ (.A(enable),
    .B(b_out[7]),
    .X(_0538_));
 sky130_fd_sc_hd__o211a_2 _2588_ (.A1(_0524_),
    .A2(b_in[7]),
    .B1(_0505_),
    .C1(_0538_),
    .X(_0072_));
 sky130_fd_sc_hd__or2_2 _2589_ (.A(enable),
    .B(b_out[8]),
    .X(_0539_));
 sky130_fd_sc_hd__o211a_2 _2590_ (.A1(_0524_),
    .A2(b_in[8]),
    .B1(_0505_),
    .C1(_0539_),
    .X(_0073_));
 sky130_fd_sc_hd__or2_2 _2591_ (.A(enable),
    .B(b_out[9]),
    .X(_0540_));
 sky130_fd_sc_hd__o211a_2 _2592_ (.A1(_0157_),
    .A2(b_in[9]),
    .B1(_1172_),
    .C1(_0540_),
    .X(_0074_));
 sky130_fd_sc_hd__or2_2 _2593_ (.A(enable),
    .B(b_out[10]),
    .X(_0541_));
 sky130_fd_sc_hd__o211a_2 _2594_ (.A1(_0524_),
    .A2(b_in[10]),
    .B1(_0509_),
    .C1(_0541_),
    .X(_0075_));
 sky130_fd_sc_hd__or2_2 _2595_ (.A(enable),
    .B(b_out[11]),
    .X(_0542_));
 sky130_fd_sc_hd__o211a_2 _2596_ (.A1(_0524_),
    .A2(b_in[11]),
    .B1(_0509_),
    .C1(_0542_),
    .X(_0076_));
 sky130_fd_sc_hd__or2_2 _2597_ (.A(enable),
    .B(b_out[12]),
    .X(_0543_));
 sky130_fd_sc_hd__o211a_2 _2598_ (.A1(_0524_),
    .A2(b_in[12]),
    .B1(_0586_),
    .C1(_0543_),
    .X(_0077_));
 sky130_fd_sc_hd__or2_2 _2599_ (.A(enable),
    .B(b_out[13]),
    .X(_0544_));
 sky130_fd_sc_hd__o211a_2 _2600_ (.A1(_0524_),
    .A2(b_in[13]),
    .B1(_0586_),
    .C1(_0544_),
    .X(_0078_));
 sky130_fd_sc_hd__or2_2 _2601_ (.A(enable),
    .B(b_out[14]),
    .X(_0545_));
 sky130_fd_sc_hd__o211a_2 _2602_ (.A1(_0524_),
    .A2(b_in[14]),
    .B1(_0505_),
    .C1(_0545_),
    .X(_0079_));
 sky130_fd_sc_hd__or4_2 _2603_ (.A(b_in[9]),
    .B(b_in[8]),
    .C(b_in[11]),
    .D(b_in[10]),
    .X(_0546_));
 sky130_fd_sc_hd__or4_2 _2604_ (.A(b_in[13]),
    .B(b_in[12]),
    .C(b_in[14]),
    .D(_0546_),
    .X(_0547_));
 sky130_fd_sc_hd__or4_2 _2605_ (.A(b_in[1]),
    .B(b_in[0]),
    .C(b_in[3]),
    .D(b_in[2]),
    .X(_0548_));
 sky130_fd_sc_hd__or4_2 _2606_ (.A(b_in[5]),
    .B(b_in[4]),
    .C(b_in[7]),
    .D(b_in[6]),
    .X(_0549_));
 sky130_fd_sc_hd__o31ai_2 _2607_ (.A1(_0547_),
    .A2(_0548_),
    .A3(_0549_),
    .B1(b_in[15]),
    .Y(_0550_));
 sky130_fd_sc_hd__nand2_2 _2608_ (.A(enable),
    .B(_0550_),
    .Y(_0551_));
 sky130_fd_sc_hd__o211a_2 _2609_ (.A1(b_out[15]),
    .A2(enable),
    .B1(_0509_),
    .C1(_0551_),
    .X(_0080_));
 sky130_fd_sc_hd__nand2_2 _2610_ (.A(_0573_),
    .B(_0550_),
    .Y(_0552_));
 sky130_fd_sc_hd__o211a_2 _2611_ (.A1(r2_sign),
    .A2(_0574_),
    .B1(_0552_),
    .C1(_0579_),
    .X(_0081_));
 sky130_fd_sc_hd__nand2_2 _2612_ (.A(_0002_),
    .B(_0582_),
    .Y(_0553_));
 sky130_fd_sc_hd__o211a_2 _2613_ (.A1(b_in[0]),
    .A2(_0582_),
    .B1(_0553_),
    .C1(_0584_),
    .X(_0082_));
 sky130_fd_sc_hd__nand2_2 _2614_ (.A(_0851_),
    .B(_0582_),
    .Y(_0554_));
 sky130_fd_sc_hd__o211a_2 _2615_ (.A1(b_in[1]),
    .A2(_0582_),
    .B1(_0554_),
    .C1(_0579_),
    .X(_0083_));
 sky130_fd_sc_hd__or2_2 _2616_ (.A(\r2_mantissa[2] ),
    .B(_0573_),
    .X(_0555_));
 sky130_fd_sc_hd__o211a_2 _2617_ (.A1(b_in[2]),
    .A2(_0582_),
    .B1(_0555_),
    .C1(_0579_),
    .X(_0084_));
 sky130_fd_sc_hd__or2_2 _2618_ (.A(\r2_mantissa[3] ),
    .B(_0573_),
    .X(_0556_));
 sky130_fd_sc_hd__o211a_2 _2619_ (.A1(b_in[3]),
    .A2(_0582_),
    .B1(_0556_),
    .C1(_0586_),
    .X(_0085_));
 sky130_fd_sc_hd__fa_1 _2620_ (.A(\r2_mantissa[13] ),
    .B(\r2_mantissa[14] ),
    .CIN(_1305_),
    .COUT(_0000_),
    .SUM(_0001_));
 sky130_fd_sc_hd__fa_1 _2621_ (.A(_0002_),
    .B(\r2_mantissa[1] ),
    .CIN(_1304_),
    .COUT(_0003_),
    .SUM(_1303_));
 sky130_fd_sc_hd__dfxtp_2 _2622_ (.CLK(clk),
    .D(_0049_),
    .Q(a_out[0]));
 sky130_fd_sc_hd__dfxtp_2 _2623_ (.CLK(clk),
    .D(_0050_),
    .Q(a_out[1]));
 sky130_fd_sc_hd__dfxtp_2 _2624_ (.CLK(clk),
    .D(_0051_),
    .Q(a_out[2]));
 sky130_fd_sc_hd__dfxtp_2 _2625_ (.CLK(clk),
    .D(_0052_),
    .Q(a_out[3]));
 sky130_fd_sc_hd__dfxtp_2 _2626_ (.CLK(clk),
    .D(_0053_),
    .Q(a_out[4]));
 sky130_fd_sc_hd__dfxtp_2 _2627_ (.CLK(clk),
    .D(_0054_),
    .Q(a_out[5]));
 sky130_fd_sc_hd__dfxtp_2 _2628_ (.CLK(clk),
    .D(_0055_),
    .Q(a_out[6]));
 sky130_fd_sc_hd__dfxtp_2 _2629_ (.CLK(clk),
    .D(_0056_),
    .Q(a_out[7]));
 sky130_fd_sc_hd__dfxtp_2 _2630_ (.CLK(clk),
    .D(_0057_),
    .Q(a_out[8]));
 sky130_fd_sc_hd__dfxtp_2 _2631_ (.CLK(clk),
    .D(_0058_),
    .Q(a_out[9]));
 sky130_fd_sc_hd__dfxtp_2 _2632_ (.CLK(clk),
    .D(_0059_),
    .Q(a_out[10]));
 sky130_fd_sc_hd__dfxtp_2 _2633_ (.CLK(clk),
    .D(_0060_),
    .Q(a_out[11]));
 sky130_fd_sc_hd__dfxtp_2 _2634_ (.CLK(clk),
    .D(_0061_),
    .Q(a_out[12]));
 sky130_fd_sc_hd__dfxtp_2 _2635_ (.CLK(clk),
    .D(_0062_),
    .Q(a_out[13]));
 sky130_fd_sc_hd__dfxtp_2 _2636_ (.CLK(clk),
    .D(_0063_),
    .Q(a_out[14]));
 sky130_fd_sc_hd__dfxtp_2 _2637_ (.CLK(clk),
    .D(_0064_),
    .Q(s1_sign_a));
 sky130_fd_sc_hd__dfxtp_2 _2638_ (.CLK(clk),
    .D(_0065_),
    .Q(b_out[0]));
 sky130_fd_sc_hd__dfxtp_2 _2639_ (.CLK(clk),
    .D(_0066_),
    .Q(b_out[1]));
 sky130_fd_sc_hd__dfxtp_2 _2640_ (.CLK(clk),
    .D(_0067_),
    .Q(b_out[2]));
 sky130_fd_sc_hd__dfxtp_2 _2641_ (.CLK(clk),
    .D(_0068_),
    .Q(b_out[3]));
 sky130_fd_sc_hd__dfxtp_2 _2642_ (.CLK(clk),
    .D(_0069_),
    .Q(b_out[4]));
 sky130_fd_sc_hd__dfxtp_2 _2643_ (.CLK(clk),
    .D(_0070_),
    .Q(b_out[5]));
 sky130_fd_sc_hd__dfxtp_2 _2644_ (.CLK(clk),
    .D(_0071_),
    .Q(b_out[6]));
 sky130_fd_sc_hd__dfxtp_2 _2645_ (.CLK(clk),
    .D(_0072_),
    .Q(b_out[7]));
 sky130_fd_sc_hd__dfxtp_2 _2646_ (.CLK(clk),
    .D(_0073_),
    .Q(b_out[8]));
 sky130_fd_sc_hd__dfxtp_2 _2647_ (.CLK(clk),
    .D(_0074_),
    .Q(b_out[9]));
 sky130_fd_sc_hd__dfxtp_2 _2648_ (.CLK(clk),
    .D(_0075_),
    .Q(b_out[10]));
 sky130_fd_sc_hd__dfxtp_2 _2649_ (.CLK(clk),
    .D(_0076_),
    .Q(b_out[11]));
 sky130_fd_sc_hd__dfxtp_2 _2650_ (.CLK(clk),
    .D(_0077_),
    .Q(b_out[12]));
 sky130_fd_sc_hd__dfxtp_2 _2651_ (.CLK(clk),
    .D(_0078_),
    .Q(b_out[13]));
 sky130_fd_sc_hd__dfxtp_2 _2652_ (.CLK(clk),
    .D(_0079_),
    .Q(b_out[14]));
 sky130_fd_sc_hd__dfxtp_2 _2653_ (.CLK(clk),
    .D(_0080_),
    .Q(b_out[15]));
 sky130_fd_sc_hd__dfxtp_2 _2654_ (.CLK(clk),
    .D(_0081_),
    .Q(r2_sign));
 sky130_fd_sc_hd__dfxtp_2 _2655_ (.CLK(clk),
    .D(_0082_),
    .Q(\r2_mantissa[0] ));
 sky130_fd_sc_hd__dfxtp_2 _2656_ (.CLK(clk),
    .D(_0083_),
    .Q(\r2_mantissa[1] ));
 sky130_fd_sc_hd__dfxtp_2 _2657_ (.CLK(clk),
    .D(_0084_),
    .Q(\r2_mantissa[2] ));
 sky130_fd_sc_hd__dfxtp_2 _2658_ (.CLK(clk),
    .D(_0085_),
    .Q(\r2_mantissa[3] ));
 sky130_fd_sc_hd__dfxtp_2 _2659_ (.CLK(clk),
    .D(_0004_),
    .Q(\r2_mantissa[4] ));
 sky130_fd_sc_hd__dfxtp_2 _2660_ (.CLK(clk),
    .D(_0005_),
    .Q(\r2_mantissa[5] ));
 sky130_fd_sc_hd__dfxtp_2 _2661_ (.CLK(clk),
    .D(_0006_),
    .Q(\r2_mantissa[6] ));
 sky130_fd_sc_hd__dfxtp_2 _2662_ (.CLK(clk),
    .D(_0007_),
    .Q(\r2_mantissa[7] ));
 sky130_fd_sc_hd__dfxtp_2 _2663_ (.CLK(clk),
    .D(_0008_),
    .Q(\r2_mantissa[8] ));
 sky130_fd_sc_hd__dfxtp_2 _2664_ (.CLK(clk),
    .D(_0009_),
    .Q(\r2_mantissa[9] ));
 sky130_fd_sc_hd__dfxtp_2 _2665_ (.CLK(clk),
    .D(_0010_),
    .Q(\r2_mantissa[10] ));
 sky130_fd_sc_hd__dfxtp_2 _2666_ (.CLK(clk),
    .D(_0011_),
    .Q(\r2_mantissa[11] ));
 sky130_fd_sc_hd__dfxtp_2 _2667_ (.CLK(clk),
    .D(_0012_),
    .Q(\r2_mantissa[12] ));
 sky130_fd_sc_hd__dfxtp_2 _2668_ (.CLK(clk),
    .D(_0013_),
    .Q(\r2_mantissa[13] ));
 sky130_fd_sc_hd__dfxtp_2 _2669_ (.CLK(clk),
    .D(_0014_),
    .Q(\r2_mantissa[14] ));
 sky130_fd_sc_hd__dfxtp_2 _2670_ (.CLK(clk),
    .D(_0015_),
    .Q(valid_s0));
 sky130_fd_sc_hd__dfxtp_2 _2671_ (.CLK(clk),
    .D(_0016_),
    .Q(\r3_prod_mant[0] ));
 sky130_fd_sc_hd__dfxtp_2 _2672_ (.CLK(clk),
    .D(_0017_),
    .Q(\r3_prod_mant[1] ));
 sky130_fd_sc_hd__dfxtp_2 _2673_ (.CLK(clk),
    .D(_0018_),
    .Q(\r3_prod_mant[2] ));
 sky130_fd_sc_hd__dfxtp_2 _2674_ (.CLK(clk),
    .D(_0019_),
    .Q(\r3_prod_mant[3] ));
 sky130_fd_sc_hd__dfxtp_2 _2675_ (.CLK(clk),
    .D(_0020_),
    .Q(\r3_prod_mant[4] ));
 sky130_fd_sc_hd__dfxtp_2 _2676_ (.CLK(clk),
    .D(_0021_),
    .Q(\r3_prod_mant[5] ));
 sky130_fd_sc_hd__dfxtp_2 _2677_ (.CLK(clk),
    .D(_0022_),
    .Q(\r3_prod_mant[6] ));
 sky130_fd_sc_hd__dfxtp_2 _2678_ (.CLK(clk),
    .D(_0023_),
    .Q(\r3_prod_mant[7] ));
 sky130_fd_sc_hd__dfxtp_2 _2679_ (.CLK(clk),
    .D(_0024_),
    .Q(\r3_prod_mant[8] ));
 sky130_fd_sc_hd__dfxtp_2 _2680_ (.CLK(clk),
    .D(_0025_),
    .Q(\r3_prod_mant[9] ));
 sky130_fd_sc_hd__dfxtp_2 _2681_ (.CLK(clk),
    .D(_0026_),
    .Q(\r3_prod_mant[10] ));
 sky130_fd_sc_hd__dfxtp_2 _2682_ (.CLK(clk),
    .D(_0027_),
    .Q(\r3_prod_mant[11] ));
 sky130_fd_sc_hd__dfxtp_2 _2683_ (.CLK(clk),
    .D(_0028_),
    .Q(\r3_prod_mant[12] ));
 sky130_fd_sc_hd__dfxtp_2 _2684_ (.CLK(clk),
    .D(_0029_),
    .Q(\r3_prod_mant[13] ));
 sky130_fd_sc_hd__dfxtp_2 _2685_ (.CLK(clk),
    .D(_0030_),
    .Q(\r3_prod_mant[14] ));
 sky130_fd_sc_hd__dfxtp_2 _2686_ (.CLK(clk),
    .D(_0031_),
    .Q(r3_prod_sign));
 sky130_fd_sc_hd__dfxtp_2 _2687_ (.CLK(clk),
    .D(_0032_),
    .Q(valid_s1));
 sky130_fd_sc_hd__dfxtp_2 _2688_ (.CLK(clk),
    .D(_0033_),
    .Q(\r4_acc[0] ));
 sky130_fd_sc_hd__dfxtp_2 _2689_ (.CLK(clk),
    .D(_0034_),
    .Q(\r4_acc[1] ));
 sky130_fd_sc_hd__dfxtp_2 _2690_ (.CLK(clk),
    .D(_0035_),
    .Q(\r4_acc[2] ));
 sky130_fd_sc_hd__dfxtp_2 _2691_ (.CLK(clk),
    .D(_0036_),
    .Q(\r4_acc[3] ));
 sky130_fd_sc_hd__dfxtp_2 _2692_ (.CLK(clk),
    .D(_0037_),
    .Q(\r4_acc[4] ));
 sky130_fd_sc_hd__dfxtp_2 _2693_ (.CLK(clk),
    .D(_0038_),
    .Q(\r4_acc[5] ));
 sky130_fd_sc_hd__dfxtp_2 _2694_ (.CLK(clk),
    .D(_0039_),
    .Q(\r4_acc[6] ));
 sky130_fd_sc_hd__dfxtp_2 _2695_ (.CLK(clk),
    .D(_0040_),
    .Q(\r4_acc[7] ));
 sky130_fd_sc_hd__dfxtp_2 _2696_ (.CLK(clk),
    .D(_0041_),
    .Q(\r4_acc[8] ));
 sky130_fd_sc_hd__dfxtp_2 _2697_ (.CLK(clk),
    .D(_0042_),
    .Q(\r4_acc[9] ));
 sky130_fd_sc_hd__dfxtp_2 _2698_ (.CLK(clk),
    .D(_0043_),
    .Q(\r4_acc[10] ));
 sky130_fd_sc_hd__dfxtp_2 _2699_ (.CLK(clk),
    .D(_0044_),
    .Q(\r4_acc[11] ));
 sky130_fd_sc_hd__dfxtp_2 _2700_ (.CLK(clk),
    .D(_0045_),
    .Q(\r4_acc[12] ));
 sky130_fd_sc_hd__dfxtp_2 _2701_ (.CLK(clk),
    .D(_0046_),
    .Q(\r4_acc[13] ));
 sky130_fd_sc_hd__dfxtp_2 _2702_ (.CLK(clk),
    .D(_0047_),
    .Q(\r4_acc[14] ));
 sky130_fd_sc_hd__dfxtp_2 _2703_ (.CLK(clk),
    .D(_0048_),
    .Q(\r4_acc[15] ));
 sky130_fd_sc_hd__conb_1 _2704_ (.LO(_1304_));
 sky130_fd_sc_hd__conb_1 _2705_ (.LO(_1305_));
 sky130_fd_sc_hd__buf_2 _2706_ (.A(s1_sign_a),
    .X(a_out[15]));
 sky130_fd_sc_hd__buf_2 _2707_ (.A(\r4_acc[0] ),
    .X(acc_out[0]));
 sky130_fd_sc_hd__buf_2 _2708_ (.A(\r4_acc[15] ),
    .X(acc_out[15]));
endmodule
