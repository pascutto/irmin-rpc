open Lwt.Infix

module Make
    (Store : Irmin.S)
    (Random : Mirage_random.S)
    (Mclock : Mirage_clock.MCLOCK)
    (Pclock : Mirage_clock.PCLOCK)
    (Time : Mirage_time.S)
    (Stack : Mirage_stack.V4) =
struct
  module Capnp_rpc_mirage = Capnp_rpc_mirage.Make (Random) (Mclock) (Stack)
  module Dns = Capnp_rpc_mirage.Network.Dns

  module Server = struct
    module Info = struct
      module Info = Irmin_mirage.Info (Pclock)

      let info ?(author = "irmin-rpc") = Info.f ~author
    end

    module Remote = struct
      type Irmin.remote += E of Git_mirage.endpoint

      let remote ?headers s = E (Git_mirage.endpoint ?headers (Uri.of_string s))
    end

    module Rpc = Irmin_rpc.Make (Store) (Info) (Remote)

    type t = { uri : Uri.t }

    let uri { uri; _ } = uri

    let create ~secret_key ?serve_tls ?(port = 1111) stack ~addr repo =
      let dns = Dns.create stack in
      let net = Capnp_rpc_mirage.network ~dns stack in
      let public_address = `TCP (addr, port) in
      let config =
        Capnp_rpc_mirage.Vat_config.create ~secret_key ?serve_tls
          ~public_address (`TCP port)
      in
      let service_id = Capnp_rpc_mirage.Vat_config.derived_id config "main" in
      let restore = Capnp_rpc_net.Restorer.single service_id (Rpc.local repo) in
      Capnp_rpc_mirage.serve net config ~restore >|= fun vat ->
      { uri = Capnp_rpc_mirage.Vat.sturdy_uri vat service_id }

    let run _t = fst @@ Lwt.wait ()
  end

  module Client = struct
    include Irmin_rpc.Client.Make (Store)

    let connect stack uri =
      let dns = Dns.create stack in
      let net = Capnp_rpc_mirage.network ~dns stack in
      let client_vat = Capnp_rpc_mirage.client_only_vat net in
      let sr = Capnp_rpc_mirage.Vat.import_exn client_vat uri in
      Capnp_rpc_lwt.Sturdy_ref.connect_exn sr
  end
end
