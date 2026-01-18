mod app;
mod context;
mod events;
mod nvim;
mod provider;
mod session;
mod settings;
mod ui;

use anyhow::Result;
use clap::Parser;
use std::io::{self, Read};

#[derive(Parser, Debug)]
#[command(name = "cmdk-rs")]
#[command(about = "AI-powered command assistant for the terminal")]
#[command(version)]
struct Args {
    /// Direct query mode (non-interactive)
    #[arg(short, long)]
    query: Option<String>,

    /// Show current context
    #[arg(short, long)]
    context: bool,

    /// Open privacy settings
    #[arg(short, long)]
    settings: bool,

    /// Neovim integration mode (path to context file)
    #[arg(long)]
    nvim: Option<String>,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Check for piped input (but not in nvim mode)
    let piped_input = if args.nvim.is_none() && !atty::is(atty::Stream::Stdin) {
        let mut input = String::new();
        io::stdin().read_to_string(&mut input)?;
        Some(input.trim().to_string())
    } else {
        None
    };

    // Initialize settings
    settings::init_settings()?;

    // Neovim mode
    if let Some(ref context_file) = args.nvim {
        if let Some(ref query) = args.query {
            // Quick query mode for Neovim
            return nvim::run_nvim_query_mode(context_file, query);
        }
        // Interactive Neovim mode
        return nvim::run_nvim_mode(context_file);
    }

    if args.context {
        // Show context mode
        let ctx = context::gather_context()?;
        println!("{}", ctx);
        return Ok(());
    }

    if args.settings {
        // Settings mode - run TUI with settings view
        app::run_settings_mode()?;
        return Ok(());
    }

    if let Some(query) = args.query {
        // Direct query mode
        return app::run_query_mode(&query);
    }

    if let Some(input) = piped_input {
        // Piped input mode
        return app::run_query_mode(&input);
    }

    // Interactive TUI mode
    app::run_interactive_mode()
}
