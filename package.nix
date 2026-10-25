{ lib
, stdenv
, makeWrapper
, swi-prolog
, src
}:

stdenv.mkDerivation {
  pname = "arch-expert";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/arch-expert $out/bin/arch-expert
    install -d $out/share/arch-expert
    cp -r prolog kb $out/share/arch-expert/
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/arch-expert \
      --set ARCH_EXPERT_HOME $out/share/arch-expert \
      --prefix PATH : ${lib.makeBinPath [ swi-prolog ]}
  '';

  meta = {
    description = "Typed Prolog expert system for system troubleshooting playbooks";
    mainProgram = "arch-expert";
    platforms = lib.platforms.unix;
  };
}
